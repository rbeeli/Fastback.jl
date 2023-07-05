equity_return(acc::Account{O,I}) where {O,I} = acc.equity / acc.initial_balance - 1.0

# note: slow
has_positions(acc::Account{O,I}) where {O,I} = any(map(x -> x.quantity != 0.0, acc.positions))

function has_position_with_inst(acc::Account{O,I}, inst::Instrument{I}) where {O,I}
    acc.positions[inst.index].quantity != 0.0
end

function has_position_with_dir(acc::Account{O,I}, inst::Instrument{I}, dir::TradeDir) where {O,I}
    sign(acc.positions[inst.index].quantity) == sign(dir)
end

# account total return based on initial balance and current equity
total_return(acc::Account{O,I}) where {O,I} = acc.equity / acc.initial_balance - 1.0

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


function execute_order!(acc::Account{O,I}, book::OrderBook{I}, order::Order{O,I})::Transaction where {O,I}
    # positions are netted using weighted average price, hence only one
    # position per instrument will be maintained
    # https://www.developer.saxo/openapi/learn/position-netting

    pos = @inbounds acc.positions[order.inst.index]

    # order execution details
    exe_price = fill_price(order.quantity, book)
    exe_quantity = order.quantity

    # realized P&L
    realized_quantity = calc_realized_quantity(pos.quantity, exe_quantity)
    realized_pnl = 0.0
    if realized_quantity != 0.0
        # order is reducing exposure (covering), calculate realized P&L
        realized_pnl = (exe_price - pos.avg_price) * realized_quantity
        pos.pnl -= realized_pnl
    end

    exe = Execution(
        book.bba.dt,
        exe_quantity,
        exe_price,
        pos.quantity,
        pos.avg_price,
        realized_pnl,
        realized_quantity)

    # update account balance
    acc.balance -= exe_quantity * exe_price

    # calculate new exposure
    new_exposure = pos.quantity + exe_quantity
    if new_exposure == 0.0
        # no more exposure
        pos.avg_price = 0.0
    else
        # update average price of position
        if sign(new_exposure) != sign(pos.quantity)
            # handle transitions from long to short and vice versa
            pos.avg_price = exe_price
        elseif abs(new_exposure) > abs(pos.quantity)
            # exposure is increased, update average price
            pos.avg_price = (pos.avg_price * pos.quantity + exe_price * exe_quantity) / new_exposure
        end
    end

    # update position quantity
    pos.quantity = new_exposure

    # update P&L of position and account equity
    update_pnl!(acc, book, pos)

    # portfolio weight at execution
    # exe.weight = exe_quantity * pos.avg_price / acc.equity

    tx = Transaction(order, exe)
    push!(pos.transactions, tx)
    push!(acc.transactions, tx)

    tx
end


function update_pnl!(acc::Account{O,I}, book::OrderBook{I}, pos::Position{O}) where {O,I}
    # update P&L and account equity
    new_pnl = calc_pnl(pos, book)
    acc.equity += new_pnl - pos.pnl
    pos.pnl = new_pnl
    return nothing
end


function update_account!(acc::Account{O,I}, data::MarketData{I}, inst::Instrument{I}) where {O,I}
    # update P&L and account equity
    book = @inbounds data.order_books[inst.index]
    pos = @inbounds acc.positions[inst.index]
    update_pnl!(acc, book, pos)
end
