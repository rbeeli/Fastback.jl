# Positional signatures are the allocation-free hot paths; keyword wrappers are
# kept for user ergonomics and forward directly.

@inline function _update_valuation!(
    acc::Account,
    pos::Position{TTime},
    dt::TTime,
    close_price::Price,
) where {TTime<:Dates.AbstractTime}
    inst = pos.inst
    settlement = inst.settlement
    settle_cash_index = inst.settle_cash_index
    qty = pos.quantity
    basis_price = pos.avg_settle_price

    new_pnl = pnl_quote(inst, qty, close_price, basis_price)

    if settlement == SettlementStyle.VariationMargin
        if pos.value_settle != 0.0
            @inbounds acc.ledger.equities[settle_cash_index] -= pos.value_settle
        end
        pos.value_settle = 0.0
        pos.value_quote = 0.0
        if qty == 0.0
            pos.avg_entry_price = zero(Price)
            pos.avg_entry_price_settle = zero(Price)
            pos.avg_settle_price = zero(Price)
            pos.pnl_quote = 0.0
            pos.pnl_settle = 0.0
            return
        end
        if new_pnl != 0.0
            settled_amount = to_settle(acc, inst, new_pnl)
            @inbounds begin
                acc.ledger.balances[settle_cash_index] += settled_amount
                acc.ledger.equities[settle_cash_index] += settled_amount
            end
            push!(acc.cashflows, Cashflow{TTime}(cfid!(acc), dt, CashflowKind.VariationMargin, settle_cash_index, settled_amount, inst.index))
        end
        pos.pnl_quote = 0.0
        pos.pnl_settle = 0.0
        pos.value_settle = 0.0
        pos.avg_settle_price = close_price
        return
    end

    new_value = value_quote(inst, qty, close_price)
    new_value_settle = to_settle(acc, inst, new_value)
    value_delta_settle = new_value_settle - pos.value_settle
    @inbounds acc.ledger.equities[settle_cash_index] += value_delta_settle
    pos.pnl_quote = new_pnl
    pos.pnl_settle = pnl_settle_asset(inst, qty, new_value_settle, pos.avg_entry_price_settle)
    pos.value_quote = new_value
    pos.value_settle = new_value_settle
    return
end

"""
Updates position valuation and account equity using the latest mark price.

For asset-settled instruments, value equals marked notional.
For variation-margin instruments, unrealized P&L is settled into cash at each update.
"""
@inline function update_valuation!(
    acc::Account,
    pos::Position{TTime};
    dt::TTime,
    close_price::Price,
) where {TTime<:Dates.AbstractTime}
    isfinite(close_price) || throw(ArgumentError("update_valuation! requires finite close_price, got $(close_price) at dt=$(dt)."))
    _update_valuation!(acc, pos, dt, close_price)
end

@inline function _update_margin!(
    acc::Account,
    pos::Position,
    close_price::Price,
)
    inst = pos.inst
    margin_cash_index = inst.margin_cash_index

    new_init_margin = margin_init_margin_ccy(acc, inst, pos.quantity, close_price)
    new_maint_margin = margin_maint_margin_ccy(acc, inst, pos.quantity, close_price)
    init_delta = new_init_margin - pos.init_margin_settle
    maint_delta = new_maint_margin - pos.maint_margin_settle
    @inbounds begin
        acc.ledger.init_margin_used[margin_cash_index] += init_delta
        acc.ledger.maint_margin_used[margin_cash_index] += maint_delta
    end
    pos.init_margin_settle = new_init_margin
    pos.maint_margin_settle = new_maint_margin
    return
end

"""
Updates margin usage for a position and corresponding account totals.

The function applies deltas to account margin vectors and stores the new
margin values on the position.
"""
@inline function update_margin!(acc::Account, pos::Position; close_price::Price)
    isfinite(close_price) || throw(ArgumentError("update_margin! requires finite close_price, got $(close_price)."))
    _update_margin!(acc, pos, close_price)
end

@inline function _update_marks!(
    acc::Account,
    pos::Position{TTime},
    dt::TTime,
    close_price::Price,
    last_price::Price,
) where {TTime<:Dates.AbstractTime}
    _update_valuation!(acc, pos, dt, close_price)
    if pos.inst.settlement != SettlementStyle.VariationMargin
        pos.avg_settle_price = pos.avg_entry_price
    end
    margin_price = margin_reference_price(acc, pos.inst, close_price, last_price)
    _update_margin!(acc, pos, margin_price)
    pos.mark_price = close_price
    pos.last_price = last_price
    pos.mark_time = dt
    return
end

"""
Updates valuation and margin for a position using the latest bid/ask/last.

Valuation uses a liquidation-aware mark (bid/ask, mid when flat; mid for VM).
Margin uses mark prices for variation-margin instruments; otherwise it uses
liquidation marks in cash accounts and `last` in margin accounts.
"""
@inline function update_marks!(
    acc::Account,
    pos::Position{TTime},
    dt::TTime,
    bid::Price,
    ask::Price,
    last::Price,
) where {TTime<:Dates.AbstractTime}
    isfinite(bid) || throw(ArgumentError("update_marks! requires finite bid, got $(bid) at dt=$(dt)."))
    isfinite(ask) || throw(ArgumentError("update_marks! requires finite ask, got $(ask) at dt=$(dt)."))
    isfinite(last) || throw(ArgumentError("update_marks! requires finite last, got $(last) at dt=$(dt)."))
    close_price = _calc_mark_price(pos.inst, pos.quantity, bid, ask)
    _update_marks!(acc, pos, dt, close_price, last)
end

@inline function _calc_mark_price(inst::Instrument, qty, bid, ask)
    # Variation margin instruments should mark at a neutral price to avoid spread bleed.
    if inst.settlement == SettlementStyle.VariationMargin
        return (bid + ask) / 2
    end
    if qty > 0
        return bid
    elseif qty < 0
        return ask
    else
        return (bid + ask) / 2
    end
end

"""
Marks an instrument by bid/ask/last, updating its position valuation, margin, and mark stamp.

Uses mid for variation-margin instruments and side-aware bid/ask for others,
then applies settlement-aware margin reference pricing.
"""
@inline function update_marks!(
    acc::Account{TTime},
    inst::Instrument{TTime},
    dt::TTime,
    bid::Price,
    ask::Price,
    last::Price,
) where {TTime<:Dates.AbstractTime}
    isfinite(bid) || throw(ArgumentError("update_marks! requires finite bid, got $(bid) at dt=$(dt)."))
    isfinite(ask) || throw(ArgumentError("update_marks! requires finite ask, got $(ask) at dt=$(dt)."))
    isfinite(last) || throw(ArgumentError("update_marks! requires finite last, got $(last) at dt=$(dt)."))
    pos = get_position(acc, inst)
    close_price = _calc_mark_price(inst, pos.quantity, bid, ask)
    _update_marks!(acc, pos, dt, close_price, last)
end

"""
Fills an order, applying cash/equity/margin deltas and returning the resulting `Trade`.
Accrues borrow fees for any eligible asset-settled spot short exposure up to `dt` and
restarts the borrow-fee clock based on the post-fill position.
Throws `OrderRejectError` when the fill is rejected (inactive instrument or risk checks).
Requires bid/ask/last to deterministically value positions and compute margin during fills.

Commission is broker-driven by default via `acc.broker`.
"""
@inline function fill_order!(
    acc::Account{TTime,TBroker},
    order::Order{TTime};
    dt::TTime,
    fill_price::Price,
    fill_qty::Quantity=0.0,      # fill quantity, if not provided, order quantity is used (complete fill)
    is_maker::Bool=false,
    allow_inactive::Bool=false,
    trade_reason::TradeReason.T=TradeReason.Normal,
    bid::Price,
    ask::Price,
    last::Price,
)::Trade{TTime} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    inst = order.inst
    isfinite(fill_price) || throw(ArgumentError("fill_order! requires finite fill_price, got $(fill_price) at dt=$(dt)."))
    isfinite(bid) || throw(ArgumentError("fill_order! requires finite bid, got $(bid) at dt=$(dt)."))
    isfinite(ask) || throw(ArgumentError("fill_order! requires finite ask, got $(ask) at dt=$(dt)."))
    isfinite(last) || throw(ArgumentError("fill_order! requires finite last, got $(last) at dt=$(dt)."))
    allow_inactive || is_active(inst, dt) || throw(OrderRejectError(OrderRejectReason.InstrumentNotAllowed))

    pos = get_position(acc, inst)
    fill_qty = fill_qty != 0 ? fill_qty : order.quantity

    mark_for_position = _calc_mark_price(inst, pos.quantity, bid, ask)
    mark_for_valuation = _calc_mark_price(inst, pos.quantity + fill_qty, bid, ask)
    margin_for_valuation = margin_reference_price(acc, inst, mark_for_valuation, last)
    needs_mark_update = isnan(pos.mark_price) || pos.mark_price != mark_for_position || pos.last_price != last || pos.mark_time != dt
    needs_mark_update && _update_marks!(acc, pos, dt, mark_for_position, last)

    _accrue_borrow_fee!(acc, pos, dt)
    pos_qty = pos.quantity
    pos_entry_price = pos.avg_entry_price
    commission_quote = broker_commission(acc.broker, inst, dt, fill_qty, fill_price; is_maker=is_maker)

    plan = plan_fill(
        acc,
        pos,
        order,
        dt,
        fill_price,
        mark_for_valuation,
        margin_for_valuation,
        fill_qty,
        commission_quote.fixed,
        commission_quote.pct,
    )

    rejection = check_fill_constraints(acc, pos, plan)
    rejection == OrderRejectReason.None || throw(OrderRejectError(rejection))

    settle_cash_index = inst.settle_cash_index
    margin_cash_index = inst.margin_cash_index
    @inbounds begin
        acc.ledger.balances[settle_cash_index] += plan.cash_delta_settle
        acc.ledger.equities[settle_cash_index] += plan.cash_delta_settle + plan.value_delta_settle
        acc.ledger.init_margin_used[margin_cash_index] += plan.init_margin_delta
        acc.ledger.maint_margin_used[margin_cash_index] += plan.maint_margin_delta
    end

    pos.avg_entry_price = plan.new_avg_entry_price_quote
    pos.avg_entry_price_settle = plan.new_avg_entry_price_settle
    pos.avg_settle_price = plan.new_avg_settle_price
    pos.quantity = plan.new_qty
    pos.pnl_quote = plan.new_pnl_quote
    pos.pnl_settle = plan.new_pnl_settle
    pos.value_quote = plan.new_value_quote
    pos.value_settle = plan.new_value_settle
    pos.init_margin_settle = plan.new_init_margin_settle
    pos.maint_margin_settle = plan.new_maint_margin_settle
    pos.mark_price = mark_for_valuation
    pos.last_price = last
    pos.mark_time = dt
    if pos.quantity < 0.0 &&
       inst.contract_kind == ContractKind.Spot &&
       inst.settlement == SettlementStyle.Asset &&
       inst.short_borrow_rate > 0.0
        pos.borrow_fee_dt = dt
    else
        pos.borrow_fee_dt = TTime(0)
    end

    # generate trade sequence number
    tid = tid!(acc)

    # create trade object
    trade = Trade(
        order,
        tid,
        dt,
        fill_price,
        plan.fill_qty,
        plan.remaining_qty,
        plan.fill_pnl_settle,
        plan.realized_qty,
        plan.commission_settle,
        plan.cash_delta_settle,
        pos_qty,
        pos_entry_price,
        trade_reason
    )

    # track last order and trade that touched the position
    pos.last_order = order
    pos.last_trade = trade

    push!(acc.trades, trade)

    trade
end

"""
Roll an open position from one instrument into another at a shared timestamp.

The helper closes the entire `from_inst` exposure first, then opens the same
signed quantity in `to_inst`. Both fills are tagged with `TradeReason.Roll`
and use explicit prices for each leg. Returns `(close_trade, open_trade)`, or
`(nothing, nothing)` when `from_inst` is already flat.
"""
function roll_position!(
    acc::Account{TTime,TBroker},
    from_inst::Instrument{TTime},
    to_inst::Instrument{TTime},
    dt::TTime;
    close_fill_price::Price,
    open_fill_price::Price,
    close_bid::Price=close_fill_price,
    close_ask::Price=close_fill_price,
    close_last::Price=close_fill_price,
    open_bid::Price=open_fill_price,
    open_ask::Price=open_fill_price,
    open_last::Price=open_fill_price,
    allow_inactive_close::Bool=false,
    allow_inactive_open::Bool=false,
)::Tuple{Union{Trade{TTime},Nothing},Union{Trade{TTime},Nothing}} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    from_inst.index == to_inst.index &&
        throw(ArgumentError("roll_position! requires distinct instruments, got $(from_inst.symbol)."))
    from_inst.base_symbol == to_inst.base_symbol ||
        throw(ArgumentError("roll_position! requires matching base_symbol, got $(from_inst.base_symbol) and $(to_inst.base_symbol)."))
    from_inst.quote_symbol == to_inst.quote_symbol ||
        throw(ArgumentError("roll_position! requires matching quote_symbol, got $(from_inst.quote_symbol) and $(to_inst.quote_symbol)."))
    from_inst.multiplier == to_inst.multiplier ||
        throw(ArgumentError("roll_position! requires matching multiplier, got $(from_inst.multiplier) and $(to_inst.multiplier)."))

    pos = get_position(acc, from_inst)
    qty = pos.quantity
    qty == 0.0 && return nothing, nothing

    close_order = Order(oid!(acc), from_inst, dt, close_fill_price, -qty)
    close_trade = fill_order!(
        acc,
        close_order;
        dt=dt,
        fill_price=close_fill_price,
        bid=close_bid,
        ask=close_ask,
        last=close_last,
        allow_inactive=allow_inactive_close,
        trade_reason=TradeReason.Roll,
    )

    open_order = Order(oid!(acc), to_inst, dt, open_fill_price, qty)
    open_trade = fill_order!(
        acc,
        open_order;
        dt=dt,
        fill_price=open_fill_price,
        bid=open_bid,
        ask=open_ask,
        last=open_last,
        allow_inactive=allow_inactive_open,
        trade_reason=TradeReason.Roll,
    )

    close_trade, open_trade
end

"""
Force-settles an expired instrument by synthetically closing any open position.

If the instrument is expired at `dt` and the position quantity is non-zero,
this generates a closing order with the provided settlement price and routes
it through `fill_order!` to record a trade and release margin.
The caller must provide a finite settlement price (typically the stored mark).

Throws `OrderRejectError` if the synthetic close is rejected by risk checks.
"""
function settle_expiry!(
    acc::Account{TTime,TBroker},
    inst::Instrument{TTime},
    dt::TTime
    ;
    settle_price=get_position(acc, inst).mark_price,
)::Union{Trade{TTime},Nothing} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    pos = get_position(acc, inst)
    (pos.quantity == 0.0 || !is_expired(inst, dt)) && return nothing

    qty = -pos.quantity
    order = Order(oid!(acc), inst, dt, settle_price, qty)
    trade = fill_order!(acc, order; dt=dt, fill_price=settle_price,
        bid=settle_price,
        ask=settle_price,
        last=settle_price,
        allow_inactive=true,
        trade_reason=TradeReason.Expiry)

    trade
end
