@inline function update_pnl!(acc::Account, pos::Position, close_price)
    # update P&L and account equity using delta of old and new P&L
    new_pnl = calc_pnl_local(pos, close_price)
    pnl_delta = new_pnl - pos.pnl_local
    cash = cash_asset(acc, pos.inst.quote_symbol)
    @inbounds acc.equities[cash.index] += pnl_delta
    pos.pnl_local = new_pnl
    return
end

@inline function update_pnl!(acc::Account, inst::Instrument, bid_price, ask_price)
    pos = get_position(acc, inst)
    close_price = is_long(pos) ? bid_price : ask_price
    update_pnl!(acc, pos, close_price)
end

@inline function fill_order!(
    acc::Account{OData,IData,CData},
    order::Order{OData,IData,TTime},
    dt::TTime,
    fill_price::Price
    ;
    fill_qty::Quantity=0.0,      # fill quantity, if not provided, order quantity is used (complete fill)
    commission::Price=0.0,       # fixed commission in quote (local) currency
    commission_pct::Price=0.0,   # percentage commission of nominal order value, e.g. 0.001 = 0.1%
)::Trade{OData,IData,TTime} where {OData,IData,CData,TTime}
    # get quote asset
    quote_cash = cash_asset(acc, order.inst.quote_symbol)

    # positions are netted using weighted average price,
    # hence only one static position per instrument is maintained
    pos = get_position(acc, order.inst)
    pos_qty = pos.quantity

    # set fill quantity if not provided
    fill_qty = fill_qty > 0 ? fill_qty : order.quantity
    remaining_qty = order.quantity - fill_qty

    # calculate absolute paid commissions in quote currency
    nominal_value = fill_price * abs(fill_qty)
    commission += commission_pct * nominal_value

    # realized P&L
    realized_qty = calc_realized_qty(pos_qty, fill_qty)
    realized_pnl = 0.0
    if realized_qty != 0.0
        # order is reducing exposure (covering), calculate realized P&L
        realized_pnl = (fill_price - pos.avg_price) * realized_qty

        # add realized P&L to account balance
        @inbounds acc.balances[quote_cash.index] += realized_pnl

        # remove realized P&L from position P&L
        pos.pnl_local -= realized_pnl
    end
    realized_pnl -= commission

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

    # subtract paid commissions from account balance and equity
    @inbounds acc.balances[quote_cash.index] -= commission
    @inbounds acc.equities[quote_cash.index] -= commission

    # update P&L of position and account equity (w/o commissions, already accounted for)
    update_pnl!(acc, pos, fill_price)

    push!(acc.trades, trade)

    trade
end
