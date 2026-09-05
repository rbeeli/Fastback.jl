const _FX_SETTLEMENT = UInt8(1)
const _FX_MARGIN = UInt8(2)

@inline function _fx_route_key(from_idx::Int, to_idx::Int)::Tuple{Int,Int}
    from_idx <= to_idx ? (from_idx, to_idx) : (to_idx, from_idx)
end

@inline function _position_fx_dependencies(acc::Account, inst::Instrument)
    spec = inst.spec
    settle_route = _fx_route_key(inst.quote_cash_index, inst.settle_cash_index)
    margin_route = _fx_route_key(inst.quote_cash_index, inst.margin_cash_index)
    settle_fx = inst.quote_cash_index != inst.settle_cash_index &&
                spec.settlement != SettlementStyle.VariationMargin
    margin_fx = inst.quote_cash_index != inst.margin_cash_index &&
                (spec.contract_kind == ContractKind.Option ||
                 acc.funding == AccountFunding.FullyFunded ||
                 spec.margin_requirement == MarginRequirement.PercentNotional)

    settle_effects = settle_fx ? _FX_SETTLEMENT | (margin_fx && settle_route == margin_route ? _FX_MARGIN : UInt8(0)) : UInt8(0)
    margin_effects = margin_fx && !(settle_fx && settle_route == margin_route) ? _FX_MARGIN : UInt8(0)
    settle_route, margin_route, settle_effects, margin_effects
end

function _register_position_events!(acc::Account, inst::Instrument)
    state = acc._event_state
    n = length(acc.positions)
    push!(state.open_slots, 0)
    push!(state.expiry_slots, 0)
    push!(state.fx_settle_slots, 0)
    push!(state.fx_margin_slots, 0)
    sizehint!(state.open_positions, n)
    push!(state.borrow_amounts, 0.0)
    push!(state.fx_effects, UInt8(0))
    sizehint!(state.fx_positions, n)

    spec = inst.spec
    if spec.contract_kind == ContractKind.Spot && spec.settlement == SettlementStyle.PrincipalExchange
        sizehint!(state.short_positions, n)
        spec.short_borrow_rate > 0.0 && sizehint!(state.borrow_positions, n)
    elseif spec.contract_kind == ContractKind.Future || spec.contract_kind == ContractKind.Option
        sizehint!(state.expiry_positions, n)
        sizehint!(state.due_expiries, n)
    end

    settle_route, margin_route, settle_effects, margin_effects = _position_fx_dependencies(acc, inst)
    if settle_effects != 0
        effects = settle_effects
        dependents = get!(_FXRouteDependents, state.fx_dependents, settle_route)
        dependents.registered_count += 1
        sizehint!(dependents.positions, dependents.registered_count)
        dependents.common_effects &= effects
    end

    if margin_effects != 0
        dependents = get!(_FXRouteDependents, state.fx_dependents, margin_route)
        dependents.registered_count += 1
        sizehint!(dependents.positions, dependents.registered_count)
        dependents.common_effects &= _FX_MARGIN
    end

    nothing
end

# Grow/shrink only at the end. Base.insert!/deleteat! may move the vector's
# storage offset and allocate repeatedly when small indices open and close.
@inline function _insert_position_index!(indices::Vector{Int}, slot::Int, idx::Int)
    push!(indices, idx)
    @inbounds for i in length(indices):-1:(slot + 1)
        indices[i] = indices[i - 1]
    end
    @inbounds indices[slot] = idx
    nothing
end

@inline function _delete_position_index!(indices::Vector{Int}, slot::Int)
    @inbounds for i in slot:(length(indices) - 1)
        indices[i] = indices[i + 1]
    end
    pop!(indices)
    nothing
end

@inline function _set_sorted_position!(indices::Vector{Int}, idx::Int, active::Bool)
    slot = searchsortedfirst(indices, idx)
    if active
        _insert_position_index!(indices, slot, idx)
    else
        _delete_position_index!(indices, slot)
    end
    nothing
end

@inline function _expiry_key(acc::Account, idx::Int)
    @inbounds acc.positions[idx].inst.spec.expiry, idx
end

# Active positions use a slot map so opening/closing an instrument never shifts
# the rest of the portfolio. Event consumers establish their required ordering.
@inline function _set_open_position!(state::_AccountEventState, idx::Int, active::Bool)
    positions = state.open_positions
    slots = state.open_slots
    if active
        push!(positions, idx)
        @inbounds slots[idx] = length(positions)
    else
        @inbounds slot = slots[idx]
        moved = pop!(positions)
        if slot <= length(positions)
            @inbounds positions[slot] = moved
            @inbounds slots[moved] = slot
        end
        @inbounds slots[idx] = 0
    end
    nothing
end

@inline function _fx_slots(state::_AccountEventState, effects::UInt8)
    effects & _FX_SETTLEMENT != 0 ? state.fx_settle_slots : state.fx_margin_slots
end

@inline function _set_fx_dependent!(
    state::_AccountEventState,
    route::Tuple{Int,Int},
    idx::Int,
    effects::UInt8,
    active::Bool,
)
    deps = state.fx_dependents[route]
    slots = _fx_slots(state, effects)
    if active
        push!(deps.positions, _FXDependentPosition(idx, effects))
        @inbounds slots[idx] = length(deps.positions)
    else
        @inbounds slot = slots[idx]
        moved = pop!(deps.positions)
        if slot <= length(deps.positions)
            @inbounds deps.positions[slot] = moved
            @inbounds _fx_slots(state, moved.effects)[moved.index] = slot
        end
        @inbounds slots[idx] = 0
    end
    deps.sorted = length(deps.positions) <= 1
    nothing
end

function _sort_fx_dependents!(state::_AccountEventState, deps::_FXRouteDependents)
    deps.sorted && return nothing
    sort!(deps.positions; by=d -> d.index, alg=QuickSort)
    @inbounds for slot in eachindex(deps.positions)
        d = deps.positions[slot]
        _fx_slots(state, d.effects)[d.index] = slot
    end
    deps.sorted = true
    nothing
end

@inline function _update_fx_membership!(acc::Account, inst::Instrument, active::Bool)
    state = acc._event_state
    settle_route, margin_route, settle_effects, margin_effects = _position_fx_dependencies(acc, inst)

    if settle_effects != 0
        effects = settle_effects
        _set_fx_dependent!(state, settle_route, inst.index, effects, active)
    end
    if margin_effects != 0
        _set_fx_dependent!(state, margin_route, inst.index, _FX_MARGIN, active)
    end
    nothing
end

# Indexed min-heap: expiry lookup is O(1), membership changes are O(log n).
@inline function _sift_expiry_up!(acc::Account, slot::Int, idx::Int)
    state = acc._event_state
    heap, slots = state.expiry_positions, state.expiry_slots
    key = _expiry_key(acc, idx)
    @inbounds while slot > 1
        parent = slot >> 1
        other = heap[parent]
        _expiry_key(acc, other) <= key && break
        heap[slot] = other
        slots[other] = slot
        slot = parent
    end
    @inbounds heap[slot] = idx
    @inbounds slots[idx] = slot
    nothing
end

@inline function _sift_expiry_down!(acc::Account, slot::Int, idx::Int)
    state = acc._event_state
    heap, slots = state.expiry_positions, state.expiry_slots
    n = length(heap)
    key = _expiry_key(acc, idx)
    @inbounds while 2 * slot <= n
        child = 2 * slot
        if child < n && _expiry_key(acc, heap[child + 1]) < _expiry_key(acc, heap[child])
            child += 1
        end
        other = heap[child]
        key <= _expiry_key(acc, other) && break
        heap[slot] = other
        slots[other] = slot
        slot = child
    end
    @inbounds heap[slot] = idx
    @inbounds slots[idx] = slot
    nothing
end

function _set_expiry_position!(acc::Account, idx::Int, active::Bool)
    state = acc._event_state
    heap, slots = state.expiry_positions, state.expiry_slots
    if active
        push!(heap, idx)
        _sift_expiry_up!(acc, length(heap), idx)
    elseif !state.bulk_expiry
        @inbounds slot = slots[idx]
        moved = pop!(heap)
        @inbounds slots[idx] = 0
        if slot <= length(heap)
            if slot > 1 && _expiry_key(acc, moved) < _expiry_key(acc, heap[slot >> 1])
                _sift_expiry_up!(acc, slot, moved)
            else
                _sift_expiry_down!(acc, slot, moved)
            end
        end
    end
    nothing
end

"""Maintain event indices after a committed quantity or entry-basis change."""
@inline function _update_position_events!(acc::Account, pos::Position, old_qty::Quantity)
    spec = pos.inst.spec
    state = acc._event_state
    qty = pos.quantity
    if spec.contract_kind == ContractKind.Option
        group = @inbounds acc.option_groups[_option_group_id(acc, pos.index)]
        group.short_count += (qty < 0.0) - (old_qty < 0.0)
    end
    changed_exposure = iszero(old_qty) != iszero(qty)
    if changed_exposure
        _set_open_position!(state, pos.index, qty != 0.0)
        _update_fx_membership!(acc, pos.inst, qty != 0.0)
    end

    if spec.contract_kind == ContractKind.Spot && spec.settlement == SettlementStyle.PrincipalExchange
        was_short = old_qty < 0.0
        is_short = qty < 0.0
        if was_short || is_short
            state.short_proceeds_dirty = true
            if was_short != is_short
                _set_sorted_position!(state.short_positions, pos.index, is_short)
                if spec.short_borrow_rate > 0.0
                    _set_sorted_position!(state.borrow_positions, pos.index, is_short)
                end
            end
        end
    elseif changed_exposure && (spec.contract_kind == ContractKind.Future || spec.contract_kind == ContractKind.Option)
        _set_expiry_position!(acc, pos.index, qty != 0.0)
    end
    nothing
end

function _collect_due_expiry_subtree!(acc::Account, dt, slot::Int)
    state = acc._event_state
    slot > length(state.expiry_positions) && return nothing
    @inbounds idx = state.expiry_positions[slot]
    is_expired(acc.positions[idx].inst, dt) || return nothing
    push!(state.due_expiries, idx)
    _collect_due_expiry_subtree!(acc, dt, 2 * slot)
    _collect_due_expiry_subtree!(acc, dt, 2 * slot + 1)
    nothing
end

"""Collect open positions due for expiry in stable registration order."""
function _collect_due_expiries!(acc::Account, dt)
    due = acc._event_state.due_expiries
    empty!(due)
    heap = acc._event_state.expiry_positions
    isempty(heap) && return due
    is_expired(acc.positions[first(heap)].inst, dt) || return due
    _collect_due_expiry_subtree!(acc, dt, 1)
    sort!(due; alg=QuickSort)
    due
end

# Bulk settlement defers removal, then compacts once. Also run on failure so
# unsettled positions remain indexed and committed closes are removed.
function _finish_bulk_expiry!(acc::Account)
    state = acc._event_state
    state.bulk_expiry = false
    heap = state.expiry_positions
    write = 0
    @inbounds for idx in heap
        if acc.positions[idx].quantity != 0.0
            write += 1
            heap[write] = idx
            state.expiry_slots[idx] = write
        else
            state.expiry_slots[idx] = 0
        end
    end
    resize!(heap, write)
    @inbounds for slot in (write >> 1):-1:1
        _sift_expiry_down!(acc, slot, heap[slot])
    end
    nothing
end

function _finish_option_expiries!(acc::Account)
    @inbounds for group_id in acc.dirty_option_groups
        group = acc.option_groups[group_id]
        filter!(idx -> acc.option_position_active[idx], group.active_positions)
        filter!(idx -> acc.option_position_active[idx], group.sorted_active_positions)
    end
    nothing
end
