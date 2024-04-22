@inline function equity_return(acc::Account{O,I}) where {O,I}
    acc.equity / acc.initial_balance - 1.0
end

# TODO: note: slow
@inline function has_positions(acc::Account{O,I}) where {O,I}
    any(map(x -> x.quantity != 0.0, acc.positions))
end

@inline function get_position(acc::Account{O,I}, inst::Instrument{I}) where {O,I}
    @inbounds acc.positions[inst.index]
end

@inline function has_position_with_inst(acc::Account{O,I}, inst::Instrument{I}) where {O,I}
    acc.positions[inst.index].quantity != 0.0
end

@inline function has_position_with_dir(acc::Account{O,I}, inst::Instrument{I}, dir::TradeDir.T) where {O,I}
    sign(acc.positions[inst.index].quantity) == sign(dir)
end

# account total return based on initial balance and current equity
@inline function total_return(acc::Account{O,I}) where {O,I}
    acc.equity / acc.initial_balance - 1.0
end

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

@inline function update_pnl!(acc::Account{O,I}, pos::Position{O}, close_price::Price) where {O,I}
    # update P&L and account equity using delta of old and new P&L
    new_pnl = calc_pnl(pos, close_price)
    acc.equity += new_pnl - pos.pnl
    pos.pnl = new_pnl
    nothing
end
