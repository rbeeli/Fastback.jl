@inline function update_valuation!(acc::Account, pos::Position, close_price)
    # update position valuation and account equity using delta of old and new value
    inst = pos.inst
    new_pnl = calc_pnl_local(pos, close_price)
    if inst.settlement == SettlementStyle.Asset
        new_value = pos.quantity * close_price * inst.multiplier
    else
        new_value = new_pnl
    end
    value_delta = new_value - pos.value_local
    quote_cash_index = inst.quote_cash_index
    @inbounds acc.equities[quote_cash_index] += value_delta
    pos.pnl_local = new_pnl
    pos.value_local = new_value
    return
end

@inline function update_pnl!(acc::Account, pos::Position, close_price)
    update_valuation!(acc, pos, close_price)
end

@inline function update_pnl!(acc::Account, inst::Instrument, bid_price, ask_price)
    pos = get_position(acc, inst)
    close_price = is_long(pos) ? bid_price : ask_price
    update_pnl!(acc, pos, close_price)
end

@inline function fill_order!(
    acc::Account{TTime,OData,IData,CData},
    order::Order{TTime,OData,IData},
    dt::TTime,
    fill_price::Price
    ;
    fill_qty::Quantity=0.0,      # fill quantity, if not provided, order quantity is used (complete fill)
    commission::Price=0.0,       # fixed commission in quote (local) currency
    commission_pct::Price=0.0,   # percentage commission of nominal order value, e.g. 0.001 = 0.1%
)::Trade{TTime,OData,IData} where {TTime<:Dates.AbstractTime,OData,IData,CData}
    inst = order.inst
    # get quote asset index
    quote_cash_index = inst.quote_cash_index

    # positions are netted using weighted average price,
    # hence only one static position per instrument is maintained
    pos = get_position(acc, inst)
    pos_qty = pos.quantity

    # set fill quantity if not provided
    fill_qty = fill_qty > 0 ? fill_qty : order.quantity
    remaining_qty = order.quantity - fill_qty

    # calculate absolute paid commissions in quote currency
    nominal_value = fill_price * abs(fill_qty) * inst.multiplier
    commission += commission_pct * nominal_value

    # realized P&L
    realized_qty = calc_realized_qty(pos_qty, fill_qty)
    realized_pnl_gross = 0.0
    if realized_qty != 0.0
        # order is reducing exposure (covering), calculate realized P&L
        realized_pnl_gross = (fill_price - pos.avg_price) * realized_qty * inst.multiplier
    end

    if inst.settlement == SettlementStyle.Asset
        cash_delta = -(fill_price * fill_qty * inst.multiplier) - commission
    else
        cash_delta = realized_pnl_gross - commission
    end
    @inbounds begin
        acc.balances[quote_cash_index] += cash_delta
        acc.equities[quote_cash_index] += cash_delta
    end
    realized_pnl = realized_pnl_gross - commission

    # generate trade sequence number
    tid = tid!(acc)

    # create trade object
    trade = Trade(
        order,
        tid,
        dt,
        fill_price,
        fill_qty,
        remaining_qty,
        realized_pnl,
        realized_qty,
        commission,
        pos_qty,
        pos.avg_price
    )

    # track last order and trade that touched the position
    pos.last_order = order
    pos.last_trade = trade

    # calculate new exposure
    new_exposure = pos_qty + fill_qty
    if new_exposure == 0.0
        # no more exposure
        pos.avg_price = zero(Price)
    else
        # update average price of position
        if sign(new_exposure) != sign(pos_qty)
            # handle transitions from long to short and vice versa
            pos.avg_price = fill_price
        elseif abs(new_exposure) > abs(pos_qty)
            # exposure is increased, update average price
            pos.avg_price = (pos.avg_price * pos_qty + fill_price * fill_qty) / new_exposure
        end
        # else: exposure is reduced, no need to update average price
    end

    # update position quantity
    pos.quantity = new_exposure

    # update P&L of position and account equity
    update_pnl!(acc, pos, fill_price)

    push!(acc.trades, trade)

    trade
end
