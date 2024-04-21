@inline equity_return(acc::Account{O,I}) where {O,I} = acc.equity / acc.initial_balance - 1.0

# TODO: note: slow
@inline has_positions(acc::Account{O,I}) where {O,I} = any(map(x -> x.quantity != 0.0, acc.positions))

@inline get_position(acc::Account{O,I}, inst::Instrument{I}) where {O,I} = @inbounds acc.positions[inst.index]

@inline function has_position_with_inst(acc::Account{O,I}, inst::Instrument{I}) where {O,I}
    acc.positions[inst.index].quantity != 0.0
end

@inline function has_position_with_dir(acc::Account{O,I}, inst::Instrument{I}, dir::TradeDir.T) where {O,I}
    sign(acc.positions[inst.index].quantity) == sign(dir)
end

# account total return based on initial balance and current equity
@inline total_return(acc::Account{O,I}) where {O,I} = acc.equity / acc.initial_balance - 1.0

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

function execute_order!(acc::Account{O,I}, order::Order{O,I}, dt::DateTime, execution_price::Price)::Transaction where {O,I}
    # positions are netted using weighted average price, hence only one
    # position per instrument will be maintained

    pos = @inbounds acc.positions[order.inst.index]

    # order execution details
    # TODO: handle partial fills
    execution_quantity = order.quantity

    # realized P&L
    realized_quantity = calc_realized_quantity(pos.quantity, execution_quantity)
    realized_pnl = 0.0
    if realized_quantity != 0.0
        # order is reducing exposure (covering), calculate realized P&L
        realized_pnl = (execution_price - pos.avg_price) * realized_quantity
        pos.pnl -= realized_pnl
    end

    exe = Execution(
        dt,
        execution_quantity,
        execution_price,
        pos.quantity,
        pos.avg_price,
        realized_pnl,
        realized_quantity)

    # update account balance
    acc.balance -= execution_quantity * execution_price

    # calculate new exposure
    new_exposure = pos.quantity + execution_quantity
    if new_exposure == 0.0
        # no more exposure
        pos.avg_price = 0.0
    else
        # update average price of position
        if sign(new_exposure) != sign(pos.quantity)
            # handle transitions from long to short and vice versa
            pos.avg_price = execution_price
        elseif abs(new_exposure) > abs(pos.quantity)
            # exposure is increased, update average price
            pos.avg_price = (pos.avg_price * pos.quantity + execution_price * execution_quantity) / new_exposure
        end
        # else: exposure is reduced, no need to update average price
    end

    # update position quantity
    pos.quantity = new_exposure

    # update P&L of position and account equity
    update_pnl!(acc, pos, execution_price)

    # portfolio weight at execution
    # exe.weight = execution_quantity * pos.avg_price / acc.equity

    tx = Transaction(order, exe)
    push!(pos.transactions, tx)
    push!(acc.transactions, tx)

    tx
end


@inline function update_pnl!(acc::Account{O,I}, pos::Position{O}, close_price::Price) where {O,I}
    # update P&L and account equity
    new_pnl = calc_pnl(pos, close_price)
    acc.equity += new_pnl - pos.pnl
    pos.pnl = new_pnl
    nothing
end


# function update_account!(acc::Account{O,I}, data::MarketData{I}, inst::Instrument{I}) where {O,I}
#     # update P&L and account equity
#     book = @inbounds data.order_books[inst.index]
#     pos = @inbounds acc.positions[inst.index]
#     update_pnl!(acc, book, pos)
# end
