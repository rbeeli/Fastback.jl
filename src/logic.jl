"""
Updates position valuation and account equity using the latest mark price.

For asset-settled instruments, value is mark-to-market notional.
For cash-settled instruments, value equals local P&L.
For variation-margin instruments, unrealized P&L is settled into cash at each update.
"""
@inline function update_valuation!(acc::Account, pos::Position, close_price)
    # update position valuation and account equity using delta of old and new value
    inst = pos.inst
    new_pnl = calc_pnl_local(pos, close_price)
    settlement = inst.settlement
    quote_cash_index = inst.quote_cash_index
    if settlement == SettlementStyle.Asset
        new_value = pos.quantity * close_price * inst.multiplier
        value_delta = new_value - pos.value_local
        @inbounds acc.equities[quote_cash_index] += value_delta
        pos.pnl_local = new_pnl
        pos.value_local = new_value
        return
    elseif settlement == SettlementStyle.Cash
        new_value = new_pnl
        value_delta = new_value - pos.value_local
        @inbounds acc.equities[quote_cash_index] += value_delta
        pos.pnl_local = new_pnl
        pos.value_local = new_value
        return
    elseif settlement == SettlementStyle.VariationMargin
        # Variation margin settlement: transfer P&L to cash and reset basis.
        if pos.value_local != 0.0
            @inbounds acc.equities[quote_cash_index] -= pos.value_local
            pos.value_local = 0.0
        end
        if pos.quantity == 0.0
            pos.avg_price = zero(Price)
            pos.pnl_local = 0.0
            return
        end
        if new_pnl != 0.0
            @inbounds begin
                acc.balances[quote_cash_index] += new_pnl
                acc.equities[quote_cash_index] += new_pnl
            end
        end
        pos.pnl_local = 0.0
        pos.value_local = 0.0
        pos.avg_price = close_price
        return
    end
    return
end

"""
Updates margin usage for a position and corresponding account totals.

The function applies deltas to account margin vectors and stores the new
margin values on the position.
"""
@inline function update_margin!(acc::Account, pos::Position, close_price)
    inst = pos.inst
    new_init_margin = margin_init_local(inst, pos.quantity, close_price)
    new_maint_margin = margin_maint_local(inst, pos.quantity, close_price)
    init_delta = new_init_margin - pos.margin_init_local
    maint_delta = new_maint_margin - pos.margin_maint_local
    quote_cash_index = inst.quote_cash_index
    @inbounds begin
        acc.init_margin_used[quote_cash_index] += init_delta
        acc.maint_margin_used[quote_cash_index] += maint_delta
    end
    pos.margin_init_local = new_init_margin
    pos.margin_maint_local = new_maint_margin
    return
end

"""
Updates valuation and margin for a position using the latest mark price.
"""
@inline function update_marks!(acc::Account, pos::Position, close_price)
    update_valuation!(acc, pos, close_price)
    update_margin!(acc, pos, close_price)
    pos.mark_price = close_price
    return
end

@inline function update_pnl!(acc::Account, pos::Position, close_price)
    update_marks!(acc, pos, close_price)
end

@inline function update_pnl!(acc::Account{TTime}, inst::Instrument{TTime}, bid_price, ask_price) where {TTime<:Dates.AbstractTime}
    pos = get_position(acc, inst)
    close_price = is_long(pos) ? bid_price : ask_price
    update_pnl!(acc, pos, close_price)
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
)::Trade{TTime} where {TTime<:Dates.AbstractTime}
    inst = order.inst
    allow_inactive || is_active(inst, dt) || throw(ArgumentError("Instrument $(inst.symbol) is not active at $dt"))
    # get quote asset index
    quote_cash_index = inst.quote_cash_index

    pos = get_position(acc, inst)
    update_marks!(acc, pos, fill_price)
    pos_qty = pos.quantity
    pos_price = pos.avg_price

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

    @inbounds begin
        acc.balances[quote_cash_index] += impact.cash_delta
        acc.equities[quote_cash_index] += impact.cash_delta
    end

    pos.avg_price = impact.new_avg_price
    pos.quantity = impact.new_qty

    # update P&L of position and account equity
    update_marks!(acc, pos, fill_price)

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
        pos_qty,
        pos_price
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
) where {TTime<:Dates.AbstractTime}
    pos = get_position(acc, inst)
    (pos.quantity == 0.0 || !is_expired(inst, dt)) && return nothing

    qty = -pos.quantity
    order = Order(oid!(acc), inst, dt, settle_price, qty)
    trade = fill_order!(acc, order, dt, settle_price; commission=commission, allow_inactive=true)

    return trade
end
