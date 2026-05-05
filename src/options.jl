@inline is_option(inst::Instrument) = inst.spec.contract_kind == ContractKind.Option

@inline function _validate_option_price(inst::Instrument, field::String, price)
    is_option(inst) || return nothing
    isfinite(price) || throw(ArgumentError("Option $(inst.spec.symbol) requires finite $(field), got $(price)."))
    price >= 0.0 || throw(ArgumentError("Option $(inst.spec.symbol) requires non-negative $(field), got $(price)."))
    nothing
end

@inline function _validate_option_mark_prices(inst::Instrument, bid, ask, last)
    is_option(inst) || return nothing
    _validate_option_price(inst, "bid", bid)
    _validate_option_price(inst, "ask", ask)
    _validate_option_price(inst, "last", last)
    nothing
end

@inline function _reset_buffer!(buf::Vector{T}, n::Int, value::T) where {T}
    resize!(buf, n)
    fill!(buf, value)
    buf
end

@inline function _copy_option_totals!(dest::Vector{Price}, src::Vector{Price})
    resize!(dest, length(src))
    copyto!(dest, src)
    dest
end

@inline function _ensure_option_margin_buffers!(scratch::OptionMarginScratch, n::Int)
    length(scratch.init_by_pos) < n && resize!(scratch.init_by_pos, n)
    length(scratch.maint_by_pos) < n && resize!(scratch.maint_by_pos, n)
    length(scratch.qty_by_pos) < n && resize!(scratch.qty_by_pos, n)
    length(scratch.mark_by_pos) < n && resize!(scratch.mark_by_pos, n)
    scratch
end

@inline function _option_group_id(acc::Account, pos_idx::Int)::Int
    pos_idx <= length(acc.option_group_id_by_pos) || return 0
    @inbounds acc.option_group_id_by_pos[pos_idx]
end

@inline function _ensure_option_override_size!(acc::Account)
    n = length(acc.positions)
    scratch = acc._option_margin_scratch
    if length(scratch.override_generation) < n
        resize!(scratch.override_generation, n)
        fill!(scratch.override_generation, 0)
        resize!(scratch.override_qty, n)
        fill!(scratch.override_qty, zero(Quantity))
        resize!(scratch.override_mark, n)
        fill!(scratch.override_mark, Price(NaN))
    end
    scratch
end

@inline function _begin_option_projection!(acc::Account)::Int
    scratch = _ensure_option_override_size!(acc)
    empty!(scratch.override_indices)
    if scratch.generation == typemax(Int)
        fill!(scratch.override_generation, 0)
        scratch.generation = 0
    end
    scratch.generation += 1
end

@inline function _set_option_projection_override!(
    acc::Account,
    generation::Int,
    pos_idx::Int,
    qty::Quantity,
    mark_price::Price,
)
    scratch = _ensure_option_override_size!(acc)
    @inbounds begin
        scratch.override_generation[pos_idx] = generation
        scratch.override_qty[pos_idx] = qty
        scratch.override_mark[pos_idx] = mark_price
    end
    @inbounds for idx in scratch.override_indices
        idx == pos_idx && return nothing
    end
    push!(scratch.override_indices, pos_idx)
    nothing
end

@inline function _option_qty_mark(acc::Account, pos_idx::Int, generation::Int)
    scratch = acc._option_margin_scratch
    if generation != 0 && @inbounds(scratch.override_generation[pos_idx] == generation)
        return @inbounds scratch.override_qty[pos_idx], scratch.override_mark[pos_idx]
    end
    pos = @inbounds acc.positions[pos_idx]
    pos.quantity, pos.mark_price
end

function _register_option_position!(acc::Account{TTime}, inst::Instrument{TTime}) where {TTime<:Dates.AbstractTime}
    spec = inst.spec
    key = OptionMarginGroupKey{TTime}(
        spec.underlying_symbol,
        spec.expiry,
        spec.multiplier,
        inst.quote_cash_index,
        inst.settle_cash_index,
        inst.margin_cash_index,
    )
    group_id = get(acc.option_group_lookup, key, 0)
    if group_id == 0
        group = OptionMarginGroup{TTime}(
            key,
            Int[],
            Int[],
            Int[],
            Int[],
            false,
            Price(NaN),
            zero(Price),
            zero(Price),
        )
        push!(acc.option_groups, group)
        push!(acc.dirty_option_group_flags, false)
        group_id = length(acc.option_groups)
        acc.option_group_lookup[key] = group_id
        underlying_key = (spec.underlying_symbol, spec.quote_symbol)
        group_ids = get!(acc.option_group_ids_by_underlying, underlying_key) do
            Int[]
        end
        push!(group_ids, group_id)
    end

    group = @inbounds acc.option_groups[group_id]
    push!(group.positions, inst.index)
    push!(group.sorted_positions, inst.index)
    sort!(group.sorted_positions; by=i -> acc.positions[i].inst.spec.strike)
    sizehint!(group.active_positions, length(group.positions))
    sizehint!(group.sorted_active_positions, length(group.positions))
    @inbounds acc.option_group_id_by_pos[inst.index] = group_id
    push!(acc.option_position_indices, inst.index)
    nothing
end

@inline function _option_position_active(acc::Account, pos_idx::Int)::Bool
    pos_idx <= length(acc.option_position_active) && @inbounds(acc.option_position_active[pos_idx])
end

function _insert_sorted_option_position!(
    acc::Account,
    positions::Vector{Int},
    pos_idx::Int,
)
    strike = @inbounds acc.positions[pos_idx].inst.spec.strike
    insert_at = lastindex(positions) + 1
    @inbounds for k in eachindex(positions)
        other_idx = positions[k]
        other_strike = acc.positions[other_idx].inst.spec.strike
        if strike < other_strike || (strike == other_strike && pos_idx < other_idx)
            insert_at = k
            break
        end
    end
    insert!(positions, insert_at, pos_idx)
    positions
end

@inline function _delete_option_position!(positions::Vector{Int}, pos_idx::Int)
    @inbounds for k in eachindex(positions)
        if positions[k] == pos_idx
            deleteat!(positions, k)
            return positions
        end
    end
    positions
end

function _set_option_position_active!(acc::Account, pos_idx::Int, active::Bool)
    group_id = _option_group_id(acc, pos_idx)
    group_id > 0 || return acc
    current = @inbounds acc.option_position_active[pos_idx]
    current == active && return acc

    group = @inbounds acc.option_groups[group_id]
    if active
        push!(group.active_positions, pos_idx)
        _insert_sorted_option_position!(acc, group.sorted_active_positions, pos_idx)
    else
        _delete_option_position!(group.active_positions, pos_idx)
        _delete_option_position!(group.sorted_active_positions, pos_idx)
    end
    @inbounds acc.option_position_active[pos_idx] = active
    acc
end

@inline function mark_option_group_dirty!(acc::Account, group_id::Int)
    group_id > 0 || return acc
    if !@inbounds(acc.dirty_option_group_flags[group_id])
        push!(acc.dirty_option_groups, group_id)
        @inbounds acc.dirty_option_group_flags[group_id] = true
    end
    @inbounds acc.option_groups[group_id].dirty = true
    acc
end

@inline function mark_option_position_dirty!(acc::Account, pos_idx::Int)
    mark_option_group_dirty!(acc, _option_group_id(acc, pos_idx))
end

function mark_option_underlying_dirty!(acc::Account, underlying_symbol::Symbol, quote_symbol::Symbol)
    cash_index(acc.ledger, quote_symbol)
    group_ids = get(acc.option_group_ids_by_underlying, (underlying_symbol, quote_symbol), nothing)
    group_ids === nothing && return acc
    @inbounds for group_id in group_ids
        group = acc.option_groups[group_id]
        isempty(group.active_positions) && continue
        mark_option_group_dirty!(acc, group_id)
    end
    acc
end

function mark_all_option_groups_dirty!(acc::Account)
    @inbounds for group_id in eachindex(acc.option_groups)
        mark_option_group_dirty!(acc, group_id)
    end
    acc
end

"""
Return the stored underlying mark used for option margin and expiry.
"""
@inline function option_underlying_price(acc::Account, underlying_symbol::Symbol, quote_symbol::Symbol)::Price
    price = get(acc.option_underlying_prices, (underlying_symbol, quote_symbol), Price(NaN))
    isfinite(price) || throw(ArgumentError("Option underlying $(underlying_symbol)/$(quote_symbol) requires a finite underlying_price."))
    price
end

@inline function option_underlying_price(acc::Account, underlying_symbol::Symbol)::Price
    throw(ArgumentError("option_underlying_price requires quote_symbol; call option_underlying_price(acc, underlying_symbol, quote_symbol) or option_underlying_price(acc, inst)."))
end

@inline function option_underlying_price(acc::Account, inst::Instrument)::Price
    is_option(inst) || throw(ArgumentError("Instrument $(inst.spec.symbol) is not an option."))
    option_underlying_price(acc, inst.spec.underlying_symbol, inst.spec.quote_symbol)
end

@inline function _set_option_underlying_price!(
    acc::Account,
    underlying_symbol::Symbol,
    quote_symbol::Symbol,
    underlying_price::Price,
)
    isfinite(underlying_price) || throw(ArgumentError("Option underlying $(underlying_symbol)/$(quote_symbol) requires finite underlying_price, got $(underlying_price)."))
    underlying_price >= 0.0 || throw(ArgumentError("Option underlying $(underlying_symbol)/$(quote_symbol) requires non-negative underlying_price, got $(underlying_price)."))
    acc.option_underlying_prices[(underlying_symbol, quote_symbol)] = underlying_price
    acc
end

@inline function _set_option_underlying_price!(
    acc::Account,
    inst::Instrument,
    underlying_price::Price,
)
    is_option(inst) || throw(ArgumentError("Instrument $(inst.spec.symbol) is not an option."))
    _set_option_underlying_price!(acc, inst.spec.underlying_symbol, inst.spec.quote_symbol, underlying_price)
end

"""
Update the underlying mark used for option margin and expiry settlement.
"""
function update_option_underlying_price!(
    acc::Account,
    underlying_symbol::Symbol,
    quote_symbol::Symbol,
    underlying_price::Real;
    recompute_option_margins::Bool=true,
)
    _set_option_underlying_price!(acc, underlying_symbol, quote_symbol, Price(underlying_price))
    if recompute_option_margins
        mark_option_underlying_dirty!(acc, underlying_symbol, quote_symbol)
        recompute_dirty_option_groups!(acc)
    end
    acc
end

function update_option_underlying_price!(
    acc::Account,
    underlying_symbol::Symbol,
    underlying_price::Real;
    recompute_option_margins::Bool=true,
)
    throw(ArgumentError("update_option_underlying_price! requires quote_symbol; call update_option_underlying_price!(acc, underlying_symbol, quote_symbol, underlying_price) or update_option_underlying_price!(acc, inst, underlying_price)."))
end

function update_option_underlying_price!(
    acc::Account,
    inst::Instrument,
    underlying_price::Real;
    recompute_option_margins::Bool=true,
)
    _set_option_underlying_price!(acc, inst, Price(underlying_price))
    if recompute_option_margins
        mark_option_underlying_dirty!(acc, inst.spec.underlying_symbol, inst.spec.quote_symbol)
        recompute_dirty_option_groups!(acc)
    end
    acc
end

"""
Intrinsic value per underlying unit for a listed option.
"""
@inline function option_intrinsic_value(inst::Instrument, underlying_price::Price)::Price
    is_option(inst) || throw(ArgumentError("Instrument $(inst.spec.symbol) is not an option."))
    isfinite(underlying_price) || throw(ArgumentError("Option $(inst.spec.symbol) requires finite underlying_price, got $(underlying_price)."))
    underlying_price >= 0.0 || throw(ArgumentError("Option $(inst.spec.symbol) requires non-negative underlying_price, got $(underlying_price)."))
    spec = inst.spec
    if spec.option_right == OptionRight.Call
        return max(underlying_price - spec.strike, 0.0)
    elseif spec.option_right == OptionRight.Put
        return max(spec.strike - underlying_price, 0.0)
    end
    throw(ArgumentError("Unsupported option right $(spec.option_right) for $(spec.symbol)."))
end

@inline function _option_otm_amount(inst::Instrument, underlying_price::Price)::Price
    spec = inst.spec
    if spec.option_right == OptionRight.Call
        return max(spec.strike - underlying_price, 0.0)
    elseif spec.option_right == OptionRight.Put
        return max(underlying_price - spec.strike, 0.0)
    end
    throw(ArgumentError("Unsupported option right $(spec.option_right) for $(spec.symbol)."))
end

"""
Conservative Reg T-style naked short option margin in quote currency.
"""
@inline function option_naked_margin_quote(
    inst::Instrument,
    qty::Quantity,
    option_price::Price,
    underlying_price::Price,
)::Price
    is_option(inst) || throw(ArgumentError("Instrument $(inst.spec.symbol) is not an option."))
    qty >= 0.0 && return 0.0
    isfinite(option_price) || throw(ArgumentError("Option $(inst.spec.symbol) requires finite option_price, got $(option_price)."))
    option_price >= 0.0 || throw(ArgumentError("Option $(inst.spec.symbol) requires non-negative option_price, got $(option_price)."))
    isfinite(underlying_price) || throw(ArgumentError("Option $(inst.spec.symbol) requires finite underlying_price, got $(underlying_price)."))
    underlying_price >= 0.0 || throw(ArgumentError("Option $(inst.spec.symbol) requires non-negative underlying_price, got $(underlying_price)."))

    spec = inst.spec
    otm = _option_otm_amount(inst, underlying_price)
    minimum_base = spec.option_right == OptionRight.Put ? spec.strike : underlying_price
    minimum = spec.option_short_margin_min_rate * minimum_base
    risk_component = max(spec.option_short_margin_rate * underlying_price - otm, minimum)
    abs(qty) * (option_price + risk_component) * spec.multiplier
end

@inline function option_naked_margin_ccy(
    acc::Account,
    inst::Instrument,
    qty::Quantity,
    option_price::Price,
)::Price
    qty >= 0.0 && return 0.0
    to_margin(acc, inst, option_naked_margin_quote(inst, qty, option_price, option_underlying_price(acc, inst)))
end

@inline function _same_option_margin_group(inst_a::Instrument, inst_b::Instrument)::Bool
    a = inst_a.spec
    b = inst_b.spec
    a.contract_kind == ContractKind.Option &&
        b.contract_kind == ContractKind.Option &&
        a.underlying_symbol == b.underlying_symbol &&
        a.expiry == b.expiry &&
        a.multiplier == b.multiplier &&
        inst_a.quote_cash_index == inst_b.quote_cash_index &&
        inst_a.settle_cash_index == inst_b.settle_cash_index &&
        inst_a.margin_cash_index == inst_b.margin_cash_index
end

@inline function _option_payoff_quote(inst::Instrument, qty::Quantity, underlying_price::Price)::Price
    qty * option_intrinsic_value(inst, underlying_price) * inst.spec.multiplier
end

function _option_group_terminal_risk_margin_ccy(
    acc::Account,
    qty_by_pos::Vector{Quantity},
    mark_by_pos::Vector{Price},
    group_idx::Vector{Int},
)::Price
    has_long = false
    has_short = false
    net_call_slope = 0.0
    current_value_quote = 0.0
    min_payoff_quote = 0.0

    @inbounds for k in eachindex(group_idx)
        idx = group_idx[k]
        pos = acc.positions[idx]
        inst = pos.inst
        qty = qty_by_pos[idx]
        mark_price = mark_by_pos[idx]
        _validate_option_price(inst, "mark_price", mark_price)

        has_long |= qty > 0.0
        has_short |= qty < 0.0
        current_value_quote += qty * mark_price * inst.spec.multiplier
        min_payoff_quote += _option_payoff_quote(inst, qty, 0.0)
        if inst.spec.option_right == OptionRight.Call
            net_call_slope += qty * inst.spec.multiplier
        end
    end

    (has_long && has_short) || return Inf
    net_call_slope < -sqrt(eps(Float64)) && return Inf

    @inbounds for k in eachindex(group_idx)
        underlying_price = acc.positions[group_idx[k]].inst.spec.strike
        payoff_quote = 0.0
        for j in eachindex(group_idx)
            idx = group_idx[j]
            pos = acc.positions[idx]
            payoff_quote += _option_payoff_quote(pos.inst, qty_by_pos[idx], underlying_price)
        end
        min_payoff_quote = min(min_payoff_quote, payoff_quote)
    end

    risk_quote = max(current_value_quote - min_payoff_quote, 0.0)
    to_margin(acc, acc.positions[group_idx[1]].inst, risk_quote)
end

@inline function _option_group_underlying_price(
    acc::Account,
    group::OptionMarginGroup,
    override_underlying_symbol::Symbol,
    override_quote_cash_index::Int,
    override_underlying_price::Price,
)::Price
    key = group.key
    if isfinite(override_underlying_price) &&
        key.underlying_symbol == override_underlying_symbol &&
        key.quote_cash_index == override_quote_cash_index
        return override_underlying_price
    end
    quote_symbol = @inbounds acc.ledger.cash[key.quote_cash_index].symbol
    option_underlying_price(acc, key.underlying_symbol, quote_symbol)
end

function _option_group_terminal_risk_margin_ccy(
    acc::Account,
    group::OptionMarginGroup,
    qty_by_pos::Vector{Quantity},
    mark_by_pos::Vector{Price},
    sorted_positions::Vector{Int},
)::Price
    has_long = false
    has_short = false
    current_value_quote = 0.0
    payoff_quote = 0.0
    slope = 0.0

    @inbounds for idx in sorted_positions
        qty = qty_by_pos[idx]
        qty == 0.0 && continue
        pos = acc.positions[idx]
        inst = pos.inst
        mark_price = mark_by_pos[idx]
        _validate_option_price(inst, "mark_price", mark_price)

        has_long |= qty > 0.0
        has_short |= qty < 0.0
        current_value_quote += qty * mark_price * inst.spec.multiplier
        if inst.spec.option_right == OptionRight.Put
            payoff_quote += qty * inst.spec.strike * inst.spec.multiplier
            slope -= qty * inst.spec.multiplier
        end
    end

    (has_long && has_short) || return Inf

    min_payoff_quote = payoff_quote
    prev_strike = 0.0
    k = firstindex(sorted_positions)
    last_k = lastindex(sorted_positions)
    @inbounds while k <= last_k
        strike = acc.positions[sorted_positions[k]].inst.spec.strike
        payoff_quote += slope * (strike - prev_strike)
        min_payoff_quote = min(min_payoff_quote, payoff_quote)

        event_slope_delta = 0.0
        while k <= last_k
            idx = sorted_positions[k]
            inst = acc.positions[idx].inst
            inst.spec.strike == strike || break
            event_slope_delta += qty_by_pos[idx] * inst.spec.multiplier
            k += 1
        end
        slope += event_slope_delta
        prev_strike = strike
    end

    slope < -sqrt(eps(Float64)) && return Inf
    risk_quote = max(current_value_quote - min_payoff_quote, 0.0)
    risk_quote * _get_rate_idx(acc, group.key.quote_cash_index, group.key.margin_cash_index)
end

function _projected_group_positions!(
    acc::Account,
    group::OptionMarginGroup,
    generation::Int,
)
    generation == 0 && return group.active_positions, group.sorted_active_positions

    positions = acc._option_margin_scratch.projected_active_positions
    empty!(positions)
    @inbounds for idx in group.sorted_active_positions
        qty, _ = _option_qty_mark(acc, idx, generation)
        qty == 0.0 && continue
        push!(positions, idx)
    end

    key = group.key
    @inbounds for idx in acc._option_margin_scratch.override_indices
        inst = acc.positions[idx].inst
        (
            inst.spec.underlying_symbol == key.underlying_symbol &&
            inst.spec.expiry == key.expiry &&
            inst.spec.multiplier == key.multiplier &&
            inst.quote_cash_index == key.quote_cash_index &&
            inst.settle_cash_index == key.settle_cash_index &&
            inst.margin_cash_index == key.margin_cash_index
        ) || continue
        _option_position_active(acc, idx) && continue
        qty, _ = _option_qty_mark(acc, idx, generation)
        qty == 0.0 && continue
        _insert_sorted_option_position!(acc, positions, idx)
    end

    positions, positions
end

function _compute_option_group_margins!(
    acc::Account,
    group::OptionMarginGroup,
    generation::Int,
    override_underlying_symbol::Symbol,
    override_quote_cash_index::Int,
    override_underlying_price::Price,
    store_underlying::Bool,
)
    scratch = acc._option_margin_scratch
    n = length(acc.positions)
    _ensure_option_margin_buffers!(scratch, n)
    init_by_pos = scratch.init_by_pos
    maint_by_pos = scratch.maint_by_pos
    qty_by_pos = scratch.qty_by_pos
    mark_by_pos = scratch.mark_by_pos
    underlying_price = Price(NaN)
    active_positions, sorted_active_positions = _projected_group_positions!(acc, group, generation)

    @inbounds for idx in active_positions
        init_by_pos[idx] = zero(Price)
        maint_by_pos[idx] = zero(Price)
        qty_by_pos[idx] = zero(Quantity)
        mark_by_pos[idx] = Price(NaN)
        pos = acc.positions[idx]
        inst = pos.inst
        qty, mark_price = _option_qty_mark(acc, idx, generation)
        qty_by_pos[idx] = qty
        qty == 0.0 && continue

        _validate_option_price(inst, "mark_price", mark_price)
        mark_by_pos[idx] = mark_price
        if qty > 0.0
            margin = abs(qty) * mark_price * inst.spec.multiplier *
                     _get_rate_idx(acc, inst.quote_cash_index, inst.margin_cash_index)
            init_by_pos[idx] = margin
            maint_by_pos[idx] = margin
        else
            if !isfinite(underlying_price)
                underlying_price = _option_group_underlying_price(
                    acc,
                    group,
                    override_underlying_symbol,
                    override_quote_cash_index,
                    override_underlying_price,
                )
                store_underlying && (group.underlying_price = underlying_price)
            end
            naked_quote = option_naked_margin_quote(inst, qty, mark_price, underlying_price)
            naked = naked_quote * _get_rate_idx(acc, inst.quote_cash_index, inst.margin_cash_index)
            init_by_pos[idx] = naked
            maint_by_pos[idx] = naked
        end
    end

    terminal_risk = _option_group_terminal_risk_margin_ccy(acc, group, qty_by_pos, mark_by_pos, sorted_active_positions)
    if isfinite(terminal_risk)
        standalone_init = 0.0
        standalone_maint = 0.0
        @inbounds for idx in active_positions
            standalone_init += init_by_pos[idx]
            standalone_maint += maint_by_pos[idx]
        end

        if standalone_init > 0.0 && terminal_risk < standalone_init
            scale = terminal_risk / standalone_init
            @inbounds for idx in active_positions
                init_by_pos[idx] *= scale
            end
        end

        if standalone_maint > 0.0 && terminal_risk < standalone_maint
            scale = terminal_risk / standalone_maint
            @inbounds for idx in active_positions
                maint_by_pos[idx] *= scale
            end
        end
    end

    init_total = 0.0
    maint_total = 0.0
    @inbounds for idx in active_positions
        init_total += init_by_pos[idx]
        maint_total += maint_by_pos[idx]
    end

    init_total, maint_total
end

const _NO_OPTION_UNDERLYING_SYMBOL = Symbol("")

@inline function _compute_option_group_margins!(
    acc::Account,
    group::OptionMarginGroup,
    generation::Int,
)
    _compute_option_group_margins!(acc, group, generation, _NO_OPTION_UNDERLYING_SYMBOL, 0, Price(NaN), true)
end

function _project_option_totals_for_groups!(
    acc::Account,
    init_dest::Vector{Price},
    maint_dest::Vector{Price},
    group_ids::Vector{Int},
    generation::Int,
    override_underlying_symbol::Symbol,
    override_quote_cash_index::Int,
    override_underlying_price::Price,
)
    _copy_option_totals!(init_dest, acc.option_init_by_cash)
    _copy_option_totals!(maint_dest, acc.option_maint_by_cash)

    @inbounds for group_id in group_ids
        group = acc.option_groups[group_id]
        init_total, maint_total = _compute_option_group_margins!(
            acc,
            group,
            generation,
            override_underlying_symbol,
            override_quote_cash_index,
            override_underlying_price,
            false,
        )
        cash_idx = group.key.margin_cash_index
        init_dest[cash_idx] += init_total - group.init_total
        maint_dest[cash_idx] += maint_total - group.maint_total
    end

    init_dest, maint_dest
end

function recompute_dirty_option_groups!(acc::Account)
    scratch = acc._option_margin_scratch
    @inbounds for group_id in acc.dirty_option_groups
        group = acc.option_groups[group_id]
        init_total, maint_total = _compute_option_group_margins!(acc, group, 0)
        margin_idx = group.key.margin_cash_index

        for idx in group.active_positions
            pos = acc.positions[idx]
            init_delta = scratch.init_by_pos[idx] - pos.init_margin_settle
            maint_delta = scratch.maint_by_pos[idx] - pos.maint_margin_settle
            acc.ledger.init_margin_used[margin_idx] += init_delta
            acc.ledger.maint_margin_used[margin_idx] += maint_delta
            pos.init_margin_settle = scratch.init_by_pos[idx]
            pos.maint_margin_settle = scratch.maint_by_pos[idx]
        end

        acc.option_init_by_cash[margin_idx] += init_total - group.init_total
        acc.option_maint_by_cash[margin_idx] += maint_total - group.maint_total
        group.init_total = init_total
        group.maint_total = maint_total
        group.dirty = false
        acc.dirty_option_group_flags[group_id] = false
    end
    empty!(acc.dirty_option_groups)
    acc
end

function _apply_option_group_margin!(
    acc::Account,
    init_by_pos::Vector{Price},
    maint_by_pos::Vector{Price},
    qty_by_pos::Vector{Quantity},
    mark_by_pos::Vector{Price},
    group_idx::Vector{Int},
)
    terminal_risk = _option_group_terminal_risk_margin_ccy(acc, qty_by_pos, mark_by_pos, group_idx)
    isfinite(terminal_risk) || return nothing

    standalone_init = 0.0
    standalone_maint = 0.0
    @inbounds for idx in group_idx
        standalone_init += init_by_pos[idx]
        standalone_maint += maint_by_pos[idx]
    end

    if standalone_init > 0.0 && terminal_risk < standalone_init
        scale = terminal_risk / standalone_init
        @inbounds for idx in group_idx
            init_by_pos[idx] *= scale
        end
    end

    if standalone_maint > 0.0 && terminal_risk < standalone_maint
        scale = terminal_risk / standalone_maint
        @inbounds for idx in group_idx
            maint_by_pos[idx] *= scale
        end
    end

    nothing
end

function _apply_option_group_margins!(
    acc::Account,
    init_by_pos::Vector{Price},
    maint_by_pos::Vector{Price},
    qty_by_pos::Vector{Quantity},
    mark_by_pos::Vector{Price},
)
    n = length(acc.positions)
    scratch = acc._option_margin_scratch
    processed = _reset_buffer!(scratch.processed, n, false)
    group_idx = scratch.group_idx
    empty!(group_idx)
    sizehint!(group_idx, n)

    @inbounds for i in 1:n
        processed[i] && continue
        qty_by_pos[i] == 0.0 && continue
        inst = acc.positions[i].inst
        is_option(inst) || continue

        empty!(group_idx)
        for j in i:n
            processed[j] && continue
            qty_by_pos[j] == 0.0 && continue
            other = acc.positions[j].inst
            _same_option_margin_group(inst, other) || continue
            push!(group_idx, j)
            processed[j] = true
        end

        length(group_idx) > 1 || continue
        _apply_option_group_margin!(acc, init_by_pos, maint_by_pos, qty_by_pos, mark_by_pos, group_idx)
    end

    nothing
end

function _option_margin_by_position(
    acc::Account;
    override_index::Int=0,
    override_qty::Quantity=Quantity(NaN),
    override_mark_price::Price=Price(NaN),
    override_indices::Union{Nothing,Vector{Int}}=nothing,
    override_qtys::Union{Nothing,Vector{Quantity}}=nothing,
    override_mark_prices::Union{Nothing,Vector{Price}}=nothing,
)
    n = length(acc.positions)
    scratch = acc._option_margin_scratch
    init_by_pos = _reset_buffer!(scratch.init_by_pos, n, zero(Price))
    maint_by_pos = _reset_buffer!(scratch.maint_by_pos, n, zero(Price))
    qty_by_pos = _reset_buffer!(scratch.qty_by_pos, n, zero(Quantity))
    mark_by_pos = _reset_buffer!(scratch.mark_by_pos, n, Price(NaN))

    @inbounds for i in 1:n
        pos = acc.positions[i]
        inst = pos.inst
        is_option(inst) || continue

        override_pos = 0
        if override_indices !== nothing
            @inbounds for j in eachindex(override_indices)
                if override_indices[j] == i
                    override_pos = j
                    break
                end
            end
        end

        qty = if override_pos != 0
            @inbounds override_qtys[override_pos]
        else
            i == override_index ? override_qty : pos.quantity
        end
        qty_by_pos[i] = qty
        qty == 0.0 && continue

        mark_price = if override_pos != 0
            @inbounds override_mark_prices[override_pos]
        else
            i == override_index ? override_mark_price : pos.mark_price
        end
        _validate_option_price(inst, "mark_price", mark_price)
        mark_by_pos[i] = mark_price
        if qty > 0.0
            init_by_pos[i] = to_margin(acc, inst, abs(qty) * mark_price * inst.spec.multiplier)
            maint_by_pos[i] = init_by_pos[i]
        else
            naked = option_naked_margin_ccy(acc, inst, qty, mark_price)
            init_by_pos[i] = naked
            maint_by_pos[i] = naked
        end
    end

    _apply_option_group_margins!(acc, init_by_pos, maint_by_pos, qty_by_pos, mark_by_pos)

    init_by_pos, maint_by_pos
end

@inline function _stored_option_margin_totals(acc::Account)
    acc.option_init_by_cash, acc.option_maint_by_cash
end

@inline function _push_unique_group!(group_ids::Vector{Int}, group_id::Int)
    group_id > 0 || return group_ids
    @inbounds for id in group_ids
        id == group_id && return group_ids
    end
    push!(group_ids, group_id)
    group_ids
end

function _option_margin_totals(
    acc::Account;
    override_index::Int=0,
    override_qty::Quantity=Quantity(NaN),
    override_mark_price::Price=Price(NaN),
    override_indices::Union{Nothing,Vector{Int}}=nothing,
    override_qtys::Union{Nothing,Vector{Quantity}}=nothing,
    override_mark_prices::Union{Nothing,Vector{Price}}=nothing,
)
    scratch = acc._option_margin_scratch
    group_ids = scratch.group_idx
    empty!(group_ids)
    generation = _begin_option_projection!(acc)

    if override_indices !== nothing
        @inbounds for j in eachindex(override_indices)
            idx = override_indices[j]
            _set_option_projection_override!(acc, generation, idx, override_qtys[j], override_mark_prices[j])
            _push_unique_group!(group_ids, _option_group_id(acc, idx))
        end
    elseif override_index != 0
        _set_option_projection_override!(acc, generation, override_index, override_qty, override_mark_price)
        _push_unique_group!(group_ids, _option_group_id(acc, override_index))
    end

    if isempty(group_ids)
        _copy_option_totals!(scratch.projected_init, acc.option_init_by_cash),
        _copy_option_totals!(scratch.projected_maint, acc.option_maint_by_cash)
    else
        _project_option_totals_for_groups!(
            acc,
            scratch.projected_init,
            scratch.projected_maint,
            group_ids,
            generation,
            _NO_OPTION_UNDERLYING_SYMBOL,
            0,
            Price(NaN),
        )
    end
end

"""
Recompute option margin usage, including bounded multi-leg payoff offsets.
"""
function recompute_option_margins!(acc::Account)
    mark_all_option_groups_dirty!(acc)
    recompute_dirty_option_groups!(acc)
end

"""
Slow reference recompute for option margin usage.
"""
function recompute_option_margins_slow!(acc::Account)
    init_by_pos, maint_by_pos = _option_margin_by_position(acc)
    fill!(acc.option_init_by_cash, zero(Price))
    fill!(acc.option_maint_by_cash, zero(Price))
    @inbounds for group in acc.option_groups
        group.init_total = zero(Price)
        group.maint_total = zero(Price)
        group.dirty = false
    end

    @inbounds for i in eachindex(acc.positions)
        pos = acc.positions[i]
        is_option(pos.inst) || continue
        margin_idx = pos.inst.margin_cash_index

        init_delta = init_by_pos[i] - pos.init_margin_settle
        maint_delta = maint_by_pos[i] - pos.maint_margin_settle
        acc.ledger.init_margin_used[margin_idx] += init_delta
        acc.ledger.maint_margin_used[margin_idx] += maint_delta
        pos.init_margin_settle = init_by_pos[i]
        pos.maint_margin_settle = maint_by_pos[i]
        acc.option_init_by_cash[margin_idx] += init_by_pos[i]
        acc.option_maint_by_cash[margin_idx] += maint_by_pos[i]
        group_id = _option_group_id(acc, i)
        if group_id > 0
            group = acc.option_groups[group_id]
            group.init_total += init_by_pos[i]
            group.maint_total += maint_by_pos[i]
        end
    end
    empty!(acc.dirty_option_groups)
    fill!(acc.dirty_option_group_flags, false)

    acc
end

function _project_option_margin_totals_after_fill(
    acc::Account,
    pos::Position,
    impact,
)
    mark_price = impact.new_qty == 0.0 ?
        Price(NaN) :
        impact.new_value_quote / (impact.new_qty * pos.inst.spec.multiplier)
    _option_margin_totals(
        acc;
        override_index=pos.inst.index,
        override_qty=impact.new_qty,
        override_mark_price=mark_price,
    )
end

"""
Cash-settle an expired option at intrinsic value and flatten the position.
"""
function settle_option_expiry!(
    acc::Account{TTime,TBroker},
    inst::Instrument{TTime},
    dt::TTime;
    underlying_price::Price=Price(NaN),
    recompute_option_margins::Bool=true,
)::Union{Trade{TTime},Nothing} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    is_option(inst) || throw(ArgumentError("settle_option_expiry! only supports Option instruments, got $(inst.spec.symbol) with $(inst.spec.contract_kind)."))

    pos = get_position(acc, inst)
    (pos.quantity == 0.0 || !is_expired(inst, dt)) && return nothing

    underlying_price = isfinite(underlying_price) ? underlying_price : option_underlying_price(acc, inst)
    _set_option_underlying_price!(acc, inst, underlying_price)

    qty_before = pos.quantity
    avg_entry_before = pos.avg_entry_price
    intrinsic = option_intrinsic_value(inst, underlying_price)
    payoff_quote = qty_before * intrinsic * inst.spec.multiplier
    payoff_settle = to_settle(acc, inst, payoff_quote)
    intrinsic_settle = to_settle(acc, inst, intrinsic)
    fill_pnl_settle = qty_before * (intrinsic_settle - pos.avg_entry_price_settle) * inst.spec.multiplier

    settle_idx = inst.settle_cash_index
    margin_idx = inst.margin_cash_index
    @inbounds begin
        acc.ledger.balances[settle_idx] += payoff_settle
        acc.ledger.equities[settle_idx] += payoff_settle - pos.value_settle
        acc.ledger.init_margin_used[margin_idx] -= pos.init_margin_settle
        acc.ledger.maint_margin_used[margin_idx] -= pos.maint_margin_settle
    end

    qty_close = -qty_before
    pos.avg_entry_price = 0.0
    pos.avg_entry_price_settle = 0.0
    pos.avg_settle_price = 0.0
    pos.quantity = 0.0
    pos.entry_commission_quote_carry = 0.0
    pos.pnl_quote = 0.0
    pos.pnl_settle = 0.0
    pos.value_quote = 0.0
    pos.value_settle = 0.0
    pos.init_margin_settle = 0.0
    pos.maint_margin_settle = 0.0
    pos.mark_price = intrinsic
    pos.last_bid = intrinsic
    pos.last_ask = intrinsic
    pos.last_price = intrinsic
    pos.mark_time = dt
    pos.borrow_fee_dt = TTime(0)

    _set_option_position_active!(acc, inst.index, false)
    mark_option_position_dirty!(acc, inst.index)
    recompute_option_margins && recompute_dirty_option_groups!(acc)

    _count_trade!(acc)
    acc.track_trades || return nothing

    order = Order(oid!(acc), inst, dt, intrinsic, qty_close)
    notional_quote = abs(intrinsic) * abs(qty_close) * inst.spec.multiplier
    notional_base = iszero(notional_quote) ? 0.0 : notional_quote * get_rate_base_ccy(acc, inst.quote_cash_index)
    trade = Trade(
        order,
        tid!(acc),
        dt,
        intrinsic,
        qty_close,
        0.0,
        notional_base,
        fill_pnl_settle,
        qty_before,
        0.0,
        0.0,
        0.0,
        payoff_settle,
        qty_before,
        avg_entry_before,
        TradeReason.Expiry,
    )
    pos.last_order = order
    pos.last_trade = trade
    push!(acc.trades, trade)
    trade
end
