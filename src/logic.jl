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
    else
        throw(ArgumentError("Unsupported settlement style $(settlement)."))
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
    return
end

@inline function update_pnl!(acc::Account, pos::Position, close_price)
    update_marks!(acc, pos, close_price)
end

@inline function update_pnl!(acc::Account, inst::Instrument, bid_price, ask_price)
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
)::Trade{TTime} where {TTime<:Dates.AbstractTime}
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
    elseif inst.settlement == SettlementStyle.Cash || inst.settlement == SettlementStyle.VariationMargin
        cash_delta = realized_pnl_gross - commission
    else
        throw(ArgumentError("Unsupported settlement style $(inst.settlement)."))
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
    update_marks!(acc, pos, fill_price)

    push!(acc.trades, trade)

    trade
end
