"""
Updates position valuation and account equity using the latest mark price.

For asset-settled instruments, value is mark-to-market notional.
For cash-settled instruments, value equals local P&L.
For variation-margin instruments, unrealized P&L is settled into cash at each update.
"""
@inline function update_valuation!(
    acc::Account,
    pos::Position{TTime},
    ;
    dt::TTime,
    close_price,
) where {TTime<:Dates.AbstractTime}
    inst = pos.inst
    settlement = inst.settlement
    settle_cash_index = inst.settle_cash_index
    qty = pos.quantity
    basis_price = pos.avg_settle_price

    new_pnl = pnl_quote(inst, qty, close_price, basis_price)
    new_value = value_quote(inst, qty, close_price, basis_price)

    if settlement == SettlementStyle.VariationMargin
        if pos.value_quote != 0.0
            @inbounds acc.equities[settle_cash_index] -= to_settle(acc, inst, pos.value_quote)
            pos.value_quote = 0.0
        end
        if qty == 0.0
            pos.avg_entry_price = zero(Price)
            pos.avg_settle_price = zero(Price)
            pos.pnl_quote = 0.0
            pos.value_quote = 0.0
            return
        end
        if new_pnl != 0.0
            settled_amount = to_settle(acc, inst, new_pnl)
            @inbounds begin
                acc.balances[settle_cash_index] += settled_amount
                acc.equities[settle_cash_index] += settled_amount
            end
            push!(acc.cashflows, Cashflow{TTime}(cfid!(acc), dt, CashflowKind.VariationMargin, settle_cash_index, settled_amount, inst.index))
        end
        pos.pnl_quote = 0.0
        pos.value_quote = 0.0
        pos.avg_settle_price = close_price
        return
    end

    value_delta = to_settle(acc, inst, new_value - pos.value_quote)
    @inbounds acc.equities[settle_cash_index] += value_delta
    pos.pnl_quote = new_pnl
    pos.value_quote = new_value
    return
end

"""
Updates margin usage for a position and corresponding account totals.

The function applies deltas to account margin vectors and stores the new
margin values on the position.
"""
@inline function update_margin!(
    acc::Account,
    pos::Position
    ;
    close_price,
)
    inst = pos.inst
    margin_cash_index = inst.settle_cash_index

    new_init_margin = margin_init_settle(acc, inst, pos.quantity, close_price)
    new_maint_margin = margin_maint_settle(acc, inst, pos.quantity, close_price)
    init_delta = new_init_margin - pos.init_margin_settle
    maint_delta = new_maint_margin - pos.maint_margin_settle
    @inbounds begin
        acc.init_margin_used[margin_cash_index] += init_delta
        acc.maint_margin_used[margin_cash_index] += maint_delta
    end
    pos.init_margin_settle = new_init_margin
    pos.maint_margin_settle = new_maint_margin
    return
end

"""
Updates valuation and margin for a position using the latest mark price.
"""
@inline function update_marks!(
    acc::Account,
    pos::Position{TTime}
    ;
    dt::TTime,
    close_price,
) where {TTime<:Dates.AbstractTime}
    update_valuation!(acc, pos; dt=dt, close_price=close_price)
    if pos.inst.settlement != SettlementStyle.VariationMargin
        pos.avg_settle_price = pos.avg_entry_price
    end
    update_margin!(acc, pos; close_price=close_price)
    pos.mark_price = close_price
    pos.mark_time = dt
    return
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

@inline function update_marks!(
    acc::Account{TTime},
    inst::Instrument{TTime}
    ;
    dt::TTime,
    bid,
    ask,
) where {TTime<:Dates.AbstractTime}
    pos = get_position(acc, inst)
    close_price = _calc_mark_price(inst, pos.quantity, bid, ask)
    update_marks!(acc, pos; dt=dt, close_price=close_price)
end

@inline function fill_order!(
    acc::Account{TTime},
    order::Order{TTime};
    dt::TTime,
    fill_price::Price,
    fill_qty::Quantity=0.0,      # fill quantity, if not provided, order quantity is used (complete fill)
    commission::Price=0.0,       # fixed commission in quote (local) currency
    commission_pct::Price=0.0,   # percentage commission of nominal order value, e.g. 0.001 = 0.1%
    allow_inactive::Bool=false,
    trade_reason::TradeReason.T=TradeReason.Normal,
    mark_price::Price=Price(NaN),
    bid::Price=Price(NaN),
    ask::Price=Price(NaN),
)::Union{Trade{TTime},OrderRejectReason.T} where {TTime<:Dates.AbstractTime}
    inst = order.inst
    allow_inactive || is_active(inst, dt) || return OrderRejectReason.InstrumentNotAllowed

    pos = get_position(acc, inst)
    fill_qty = fill_qty != 0 ? fill_qty : order.quantity

    mark_for_valuation = if !isnan(mark_price)
        mark_price
    elseif !isnan(bid) && !isnan(ask)
        _calc_mark_price(inst, pos.quantity + fill_qty, bid, ask)
    elseif pos.mark_time == dt && !isnan(pos.mark_price)
        pos.mark_price
    else
        fill_price
    end

    needs_mark_update = isnan(pos.mark_price) || pos.mark_price != mark_for_valuation || pos.mark_time != dt
    needs_mark_update && update_marks!(acc, pos; dt=dt, close_price=mark_for_valuation)
    pos_qty = pos.quantity
    pos_entry_price = pos.avg_entry_price

    plan = plan_fill(
        acc,
        pos,
        order,
        dt=dt,
        fill_price=fill_price,
        mark_price=mark_for_valuation,
        fill_qty=fill_qty,
        commission=commission,
        commission_pct=commission_pct,
    )

    if acc.mode == AccountMode.Cash
        cash_reject = check_cash_account(acc, pos, inst, plan)
        cash_reject == OrderRejectReason.None || return cash_reject
    end

    rejection = check_fill_constraints(acc, pos, plan)
    rejection == OrderRejectReason.None || return rejection
    
    settle_cash_index = inst.settle_cash_index
    @inbounds begin
        acc.balances[settle_cash_index] += plan.cash_delta
        acc.equities[settle_cash_index] += plan.cash_delta + plan.value_delta_settle
        acc.init_margin_used[settle_cash_index] += plan.init_margin_delta
        acc.maint_margin_used[settle_cash_index] += plan.maint_margin_delta
    end

    pos.avg_entry_price = plan.new_avg_entry_price
    pos.avg_settle_price = plan.new_avg_settle_price
    pos.quantity = plan.new_qty
    pos.pnl_quote = plan.new_pnl_quote
    pos.value_quote = plan.new_value_quote
    pos.init_margin_settle = plan.new_init_margin_settle
    pos.maint_margin_settle = plan.new_maint_margin_settle
    pos.mark_price = mark_for_valuation
    pos.mark_time = dt

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
        plan.realized_pnl_net,
        plan.realized_qty,
        plan.commission,
        plan.cash_delta,
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
Force-settles an expired instrument by synthetically closing any open position.

If the instrument is expired at `dt` and the position quantity is non-zero,
this generates a closing order with the provided settlement price and routes
it through `fill_order!` to record a trade and release margin. Physical-delivery
instruments can be rejected by setting `physical_expiry_policy=PhysicalExpiryPolicy.Error`.
"""
function settle_expiry!(
    acc::Account{TTime},
    inst::Instrument{TTime},
    dt::TTime
    ;
    settle_price=get_position(acc, inst).mark_price,
    commission::Price=0.0,
    commission_pct::Price=0.0,
    physical_expiry_policy::PhysicalExpiryPolicy.T=PhysicalExpiryPolicy.Close,
)::Union{Trade{TTime},OrderRejectReason.T,Nothing} where {TTime<:Dates.AbstractTime}
    pos = get_position(acc, inst)
    (pos.quantity == 0.0 || !is_expired(inst, dt)) && return nothing
    if inst.delivery_style == DeliveryStyle.PhysicalDeliver && physical_expiry_policy == PhysicalExpiryPolicy.Error
        throw(ArgumentError("Expiry for $(inst.symbol) requires physical delivery; pass physical_expiry_policy=PhysicalExpiryPolicy.Close to auto-close."))
    end

    qty = -pos.quantity
    order = Order(oid!(acc), inst, dt, settle_price, qty)
    trade = fill_order!(acc, order; dt=dt, fill_price=settle_price,
        commission=commission,
        commission_pct=commission_pct,
        allow_inactive=true,
        trade_reason=TradeReason.Expiry)

    trade
end
