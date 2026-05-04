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
    recompute_option_margins && recompute_option_margins!(acc)
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
    recompute_option_margins && recompute_option_margins!(acc)
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

function _stored_option_margin_totals(acc::Account)
    scratch = acc._option_margin_scratch
    n = length(acc.ledger.init_margin_used)
    init = _reset_buffer!(scratch.current_init, n, zero(Price))
    maint = _reset_buffer!(scratch.current_maint, n, zero(Price))

    @inbounds for pos in acc.positions
        is_option(pos.inst) || continue
        margin_idx = pos.inst.margin_cash_index
        init[margin_idx] += pos.init_margin_settle
        maint[margin_idx] += pos.maint_margin_settle
    end

    init, maint
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
    init_by_pos, maint_by_pos = _option_margin_by_position(
        acc;
        override_index=override_index,
        override_qty=override_qty,
        override_mark_price=override_mark_price,
        override_indices=override_indices,
        override_qtys=override_qtys,
        override_mark_prices=override_mark_prices,
    )
    scratch = acc._option_margin_scratch
    n = length(acc.ledger.init_margin_used)
    init = _reset_buffer!(scratch.projected_init, n, zero(Price))
    maint = _reset_buffer!(scratch.projected_maint, n, zero(Price))

    @inbounds for i in eachindex(acc.positions)
        inst = acc.positions[i].inst
        is_option(inst) || continue
        margin_idx = inst.margin_cash_index
        init[margin_idx] += init_by_pos[i]
        maint[margin_idx] += maint_by_pos[i]
    end

    init, maint
end

"""
Recompute option margin usage, including bounded multi-leg payoff offsets.
"""
function recompute_option_margins!(acc::Account)
    init_by_pos, maint_by_pos = _option_margin_by_position(acc)

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
    end

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

    recompute_option_margins && recompute_option_margins!(acc)

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
