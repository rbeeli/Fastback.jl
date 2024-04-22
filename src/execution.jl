@inline function calc_realized_pnl(exe::Execution)
    exe.realized_pnl
end

# @inline function calc_realized_return(order::Order; zero_value=0.0)
#     order.execution.realized_pnl != 0 ? calc_realized_pnl(order) / (order.execution.pos_avg_price * abs(order.execution.realized_quantity)) : zero_value
# end

@inline function calc_realized_price_return(exe::Execution; zero_value=0.0)
    exe.realized_pnl != 0 ? sign(exe.pos_quantity) * (exe.price / exe.pos_avg_price - 1.0) : zero_value
end

function fill_order!(acc::Account{O,I}, order::Order{O,I}, dt::DateTime, fill_price::Price; fill_quantity=NaN)::Transaction where {O,I}
    # positions are netted using weighted average price,
    # hence only one static position per instrument is maintained

    pos = @inbounds acc.positions[order.inst.index]

    # set fill quantity if not provided
    if isnan(fill_quantity)
        fill_quantity = order.quantity
    end

    # realized P&L
    realized_quantity = calc_realized_quantity(pos.quantity, fill_quantity)
    realized_pnl = 0.0
    if realized_quantity != 0.0
        # order is reducing exposure (covering), calculate realized P&L
        realized_pnl = (fill_price - pos.avg_price) * realized_quantity
        pos.pnl -= realized_pnl
    end

    exe = Execution(
        dt,
        fill_quantity,
        fill_price,
        pos.quantity,
        pos.avg_price,
        realized_pnl,
        realized_quantity)

    # update account balance
    acc.balance -= fill_quantity * fill_price

    # calculate new exposure
    new_exposure = pos.quantity + fill_quantity
    if new_exposure == 0.0
        # no more exposure
        pos.avg_price = 0.0
    else
        # update average price of position
        if sign(new_exposure) != sign(pos.quantity)
            # handle transitions from long to short and vice versa
            pos.avg_price = fill_price
        elseif abs(new_exposure) > abs(pos.quantity)
            # exposure is increased, update average price
            pos.avg_price = (pos.avg_price * pos.quantity + fill_price * fill_quantity) / new_exposure
        end
        # else: exposure is reduced, no need to update average price
    end

    # update position quantity
    pos.quantity = new_exposure

    # update P&L of position and account equity
    update_pnl!(acc, pos, fill_price)

    # portfolio weight at execution
    # exe.weight = fill_quantity * pos.avg_price / acc.equity

    tx = Transaction(order, exe)
    push!(pos.transactions, tx)
    push!(acc.transactions, tx)

    tx
end
