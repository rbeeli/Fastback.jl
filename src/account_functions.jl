@inline equity_return(acc::Account) = acc.equity / acc.initial_balance - 1.0

# note: slow
@inline has_positions(acc::Account) = any(map(x -> x.quantity != 0.0, acc.positions))

function has_position_with_inst(acc::Account, inst::Instrument)
    acc.positions[inst.index].quantity != 0.0
end

function has_position_with_dir(acc::Account, inst::Instrument, dir::TradeDir)
    sign(acc.positions[inst.index].quantity) == sign(dir)
end

# account total return based on initial balance and current equity
@inline total_return(acc::Account) = acc.equity / acc.initial_balance - 1.0

# @inline total_pnl_net(acc::Account) = sum(map(pnl_net, acc.closed_positions))
# @inline total_pnl_gross(acc::Account) = sum(map(pnl_gross, acc.closed_positions))

# @inline count_winners_net(acc::Account) = count(map(x -> pnl_net(x) > 0.0, acc.closed_positions))
# @inline count_winners_gross(acc::Account) = count(map(x -> pnl_gross(x) > 0.0, acc.closed_positions))

# # Dates.func(nbbo.dt) accessor shortcuts, e.g. year(nbbo), day(nbbo), hour(nbbo)
# for func in (:year, :month, :day, :hour, :minute, :second, :millisecond, :microsecond, :nanosecond)
#     name = string(func)
#     @eval begin
#         $func(ba::BidAsk)::Int64 = Dates.$func(ba.dt)
#     end
# end


function execute_order!(acc::Account, book::OrderBook, order::Order)
    # positions are netted using weighted average price, hence only one
    # position per instrument will be maintained
    # https://www.developer.saxo/openapi/learn/position-netting

    pos = @inbounds acc.positions[order.inst.index]

    # order execution details
    exe = order.execution
    exe.dt = book.bba.dt
    exe.pos_quantity = pos.quantity
    exe.pos_avg_price = pos.avg_price
    exe.price = fill_price(order.quantity, book)
    exe.quantity = order.quantity

    # realized P&L
    exe.realized_quantity = calc_realized_quantity(pos.quantity, exe.quantity)
    if exe.realized_quantity != 0.0
        # order is reducing exposure (covering), calculate realized P&L
        exe.realized_pnl = (exe.pos_avg_price - exe.price) * -exe.realized_quantity
        pos.pnl -= exe.realized_pnl
    end

    # update account balance
    acc.balance -= exe.quantity * exe.price
    
    # calculate new exposure
    new_exposure = pos.quantity + exe.quantity
    if new_exposure == 0.0
        # no more exposure
        pos.avg_price = 0.0
    else
        # update average price (if exposure is increased)
        pos.avg_price = calc_weighted_avg_price(pos.avg_price, pos.quantity, exe.price, exe.quantity)
    end

    # update position quantity
    pos.quantity = new_exposure

    # update P&L of position and account equity
    update_pnl!(acc, book, pos)

    # exe.weight = exe.quantity * exe.price / acc.equity

    # add order to history
    push!(pos.orders_history, order)
    push!(acc.orders_history, order)

    return nothing
end


@inline function update_pnl!(acc::Account, book::OrderBook, pos::Position)
    # update P&L and account equity
    acc.equity -= pos.pnl
    pos.pnl = calc_pnl(pos, book)
    acc.equity += pos.pnl
    return nothing
end


function update_account!(acc::Account, data::MarketData, inst::Instrument)
    # update P&L and account equity
    book = @inbounds data.order_books[inst.index]
    pos = @inbounds acc.positions[inst.index]
    update_pnl!(acc, book, pos)
end
