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
    # update position valuation and account equity using delta of old and new value
    inst = pos.inst
    settlement = inst.settlement
    settle_cash_index = inst.settle_cash_index
    quote_cash_index = inst.quote_cash_index
    rate_q_to_settle = get_rate(acc, quote_cash_index, settle_cash_index)
    if settlement == SettlementStyle.Asset
        new_pnl = calc_pnl_local(pos, close_price)
        new_value = pos.quantity * close_price * inst.multiplier
        value_delta = (new_value - pos.value_local) * rate_q_to_settle
        @inbounds acc.equities[settle_cash_index] += value_delta
        pos.pnl_local = new_pnl
        pos.value_local = new_value
        return
    elseif settlement == SettlementStyle.Cash
        new_pnl = calc_pnl_local(pos, close_price)
        new_value = new_pnl
        value_delta = (new_value - pos.value_local) * rate_q_to_settle
        @inbounds acc.equities[settle_cash_index] += value_delta
        pos.pnl_local = new_pnl
        pos.value_local = new_value
        return
    elseif settlement == SettlementStyle.VariationMargin
        # Variation margin settlement: transfer P&L to cash and reset settle basis.
        if pos.value_local != 0.0
            @inbounds acc.equities[settle_cash_index] -= pos.value_local * rate_q_to_settle
            pos.value_local = 0.0
        end
        if pos.quantity == 0.0
            pos.avg_entry_price = zero(Price)
            pos.avg_settle_price = zero(Price)
            pos.pnl_local = 0.0
            pos.value_local = 0.0
            return
        end
        new_pnl = calc_pnl_local(pos, close_price)
        if new_pnl != 0.0
            settled_amount = new_pnl * rate_q_to_settle
            @inbounds begin
                acc.balances[settle_cash_index] += settled_amount
                acc.equities[settle_cash_index] += settled_amount
            end
            push!(acc.cashflows, Cashflow{TTime}(cfid!(acc), dt, CashflowKind.VariationMargin, settle_cash_index, settled_amount, inst.index))
        end
        pos.pnl_local = 0.0
        pos.value_local = 0.0
        pos.avg_settle_price = close_price
        return
    end
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

    # Fixed-per-contract margins are already in settlement currency.
    # Percent-notional margins are in quote currency and need quote→settle FX.
    rate_to_settle = inst.margin_mode == MarginMode.FixedPerContract ? 1.0 : get_rate(acc, inst.quote_cash_index, margin_cash_index)

    new_init_margin = margin_init_local(inst, pos.quantity, close_price) * rate_to_settle
    new_maint_margin = margin_maint_local(inst, pos.quantity, close_price) * rate_to_settle
    init_delta = new_init_margin - pos.margin_init_local
    maint_delta = new_maint_margin - pos.margin_maint_local
    @inbounds begin
        acc.init_margin_used[margin_cash_index] += init_delta
        acc.maint_margin_used[margin_cash_index] += maint_delta
    end
    pos.margin_init_local = new_init_margin
    pos.margin_maint_local = new_maint_margin
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
    return
end

@inline function _calc_mark_price(pos::Position, bid, ask)
    # Variation margin instruments should mark at a neutral price to avoid spread bleed.
    if pos.inst.settlement == SettlementStyle.VariationMargin
        return (bid + ask) / 2
    end
    is_long(pos) ? bid : ask
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
    close_price = _calc_mark_price(pos, bid, ask)
    update_marks!(acc, pos; dt=dt, close_price=close_price)
end

@inline function fill_order!(
    acc::Account{TTime},
    order::Order{TTime},
    dt::TTime,
    fill_price::Price
    ;
    fill_qty::Quantity=0.0,      # fill quantity, if not provided, order quantity is used (complete fill)
    commission::Price=0.0,       # fixed commission in quote (local) currency
    commission_pct::Price=0.0,   # percentage commission of nominal order value, e.g. 0.001 = 0.1%
    allow_inactive::Bool=false,
    trade_reason::TradeReason.T=TradeReason.Normal,
)::Union{Trade{TTime},OrderRejectReason.T} where {TTime<:Dates.AbstractTime}
    inst = order.inst
    allow_inactive || is_active(inst, dt) || return OrderRejectReason.InstrumentNotAllowed
    # get cash indexes
    settle_cash_index = inst.settle_cash_index

    pos = get_position(acc, inst)
    update_marks!(acc, pos; dt=dt, close_price=fill_price)
    pos_qty = pos.quantity
    pos_entry_price = pos.avg_entry_price

    impact = compute_fill_impact(
        acc,
        pos,
        order,
        dt,
        fill_price;
        fill_qty=fill_qty,
        commission=commission,
        commission_pct=commission_pct,
    )

    if acc.mode == AccountMode.Cash
        cash_reject = check_cash_account(acc, pos, inst, impact)
        cash_reject == OrderRejectReason.None || return cash_reject
    end

    rejection = check_fill_constraints(acc, pos, impact)
    rejection == OrderRejectReason.None || return rejection

    @inbounds begin
        acc.balances[settle_cash_index] += impact.cash_delta
        acc.equities[settle_cash_index] += impact.cash_delta
    end

    old_qty = pos.quantity
    pos.avg_entry_price = impact.new_avg_entry_price
    pos.quantity = impact.new_qty
    if pos.quantity == 0.0
        pos.avg_entry_price = 0.0
        pos.avg_settle_price = 0.0
    elseif old_qty == 0.0
        pos.avg_settle_price = pos.inst.settlement == SettlementStyle.VariationMargin ? fill_price : pos.avg_entry_price
    elseif sign(old_qty) != sign(pos.quantity)
        pos.avg_settle_price = fill_price
    elseif pos.inst.settlement != SettlementStyle.VariationMargin && abs(pos.quantity) > abs(old_qty)
        pos.avg_settle_price = pos.avg_entry_price
    end

    # update P&L of position and account equity
    update_marks!(acc, pos; dt=dt, close_price=fill_price)

    # generate trade sequence number
    tid = tid!(acc)

    # create trade object
    trade = Trade(
        order,
        tid,
        dt,
        fill_price,
        impact.fill_qty,
        impact.remaining_qty,
        impact.realized_pnl_net,
        impact.realized_qty,
        impact.commission,
        impact.cash_delta,
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
it through `fill_order!` to record a trade and release margin.
"""
function settle_expiry!(
    acc::Account{TTime},
    inst::Instrument{TTime},
    dt::TTime
    ;
    settle_price=get_position(acc, inst).mark_price,
    commission::Price=0.0,
)::Union{Trade{TTime},OrderRejectReason.T,Nothing} where {TTime<:Dates.AbstractTime}
    pos = get_position(acc, inst)
    (pos.quantity == 0.0 || !is_expired(inst, dt)) && return nothing

    qty = -pos.quantity
    order = Order(oid!(acc), inst, dt, settle_price, qty)
    trade = fill_order!(acc, order, dt, settle_price; commission=commission, allow_inactive=true, trade_reason=TradeReason.Expiry)

    trade
end
