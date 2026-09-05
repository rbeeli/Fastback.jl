const _FX_SETTLEMENT = UInt8(1)
const _FX_MARGIN = UInt8(2)

@inline function _fx_route_key(from_idx::Int, to_idx::Int)::Tuple{Int,Int}
    from_idx <= to_idx ? (from_idx, to_idx) : (to_idx, from_idx)
end

function _register_position_events!(acc::Account, inst::Instrument)
    state = acc._event_state
    n = length(acc.positions)
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

    settle_route = _fx_route_key(inst.quote_cash_index, inst.settle_cash_index)
    margin_route = _fx_route_key(inst.quote_cash_index, inst.margin_cash_index)
    settle_fx = inst.quote_cash_index != inst.settle_cash_index &&
                spec.settlement != SettlementStyle.VariationMargin
    margin_fx = inst.quote_cash_index != inst.margin_cash_index &&
                (spec.contract_kind == ContractKind.Option ||
                 acc.funding == AccountFunding.FullyFunded ||
                 spec.margin_requirement == MarginRequirement.PercentNotional)

    if settle_fx
        effects = _FX_SETTLEMENT | (margin_fx && settle_route == margin_route ? _FX_MARGIN : UInt8(0))
        dependents = get!(_FXRouteDependents, state.fx_dependents, settle_route)
        push!(dependents.positions, _FXDependentPosition(inst.index, effects))
        dependents.common_effects &= effects
    end

    if margin_fx && !(settle_fx && settle_route == margin_route)
        dependents = get!(_FXRouteDependents, state.fx_dependents, margin_route)
        push!(dependents.positions, _FXDependentPosition(inst.index, _FX_MARGIN))
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

"""Maintain event indices after a committed quantity or entry-basis change."""
@inline function _update_position_events!(acc::Account, pos::Position, old_qty::Quantity)
    spec = pos.inst.spec
    state = acc._event_state
    qty = pos.quantity

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
    elseif spec.contract_kind == ContractKind.Future || spec.contract_kind == ContractKind.Option
        if iszero(old_qty) != iszero(qty)
            indices = state.expiry_positions
            slot = searchsortedfirst(indices, pos.index; by=idx -> _expiry_key(acc, idx))
            if qty != 0.0
                _insert_position_index!(indices, slot, pos.index)
            else
                _delete_position_index!(indices, slot)
            end
        end
    end

    nothing
end

"""Collect open positions due for expiry in stable registration order."""
function _collect_due_expiries!(acc::Account, dt)
    state = acc._event_state
    due = state.due_expiries
    empty!(due)

    @inbounds for idx in state.expiry_positions
        is_expired(acc.positions[idx].inst, dt) || break
        push!(due, idx)
    end

    sort!(due; alg=QuickSort)
    due
end
