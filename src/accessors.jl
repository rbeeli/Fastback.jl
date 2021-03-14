
@inline midprice(ba::BidAsk) = (ba.bid + ba.ask) / 2.0
@inline midprice(bid::Price, ask::Price) = (bid + ask) / 2.0

@inline spread(ba::BidAsk) = (ba.ask - ba.bid)
@inline spread(bid::Price, ask::Price) = (ask - bid)

@inline is_long(dir::TradeDir) = dir === Long
@inline is_long(pos::Position) = pos.dir === Long

@inline is_short(dir::TradeDir) = dir === Short
@inline is_short(pos::Position) = pos.dir === Short

@inline get_open_price(pos::Position) = is_long(pos.dir) ? pos.open_quotes.ask : (is_short(pos.dir) ? pos.open_quotes.bid : NaN)
@inline get_open_price(dir::TradeDir, ba::BidAsk) = is_long(dir) ? ba.ask : (is_short(dir) ? ba.bid : NaN)
@inline get_close_price(pos::Position) = is_long(pos.dir) ? pos.last_quotes.bid : (is_short(pos.dir) ? pos.last_quotes.ask : NaN)
@inline get_close_price(dir::TradeDir, ba::BidAsk) = is_long(dir) ? ba.bid : (is_short(dir) ? ba.ask : NaN)

# size negative for shorts, thus works for both long and short
@inline get_pnl_net(pos::Position) = pos.size * (pos.last_price - pos.open_price)
@inline get_pnl_gross(pos::Position) = pos.size * (midprice(pos.last_quotes) - midprice(pos.open_quotes))

# size negative for shorts, thus works for both long and short
@inline get_return_net(pos::Position) = sign(pos.size) * (pos.last_price - pos.open_price) / pos.open_price
@inline get_return_gross(pos::Position) = sign(pos.size) * ((midprice(pos.last_quotes) - midprice(pos.open_quotes)) / midprice(pos.open_quotes))

@inline has_open_positions(acc::Account) = length(acc.open_positions) > 0
@inline has_closed_positions(acc::Account) = length(acc.closed_positions) > 0

# @inline has_pending_orders(acc::Account)::Bool = acc.place_orders_count + acc.close_orders_count > 0
# @inline has_pending_place_orders(acc::Account)::Bool = acc.place_orders_count > 0
# @inline has_pending_close_orders(acc::Account)::Bool = acc.close_orders_count > 0

@inline total_ret_net(acc::Account) = sum(map(get_return_net, acc.closed_positions))
@inline total_ret_gross(acc::Account) = sum(map(get_return_gross, acc.closed_positions))

@inline total_pnl_net(acc::Account) = sum(map(get_pnl_net, acc.closed_positions))
@inline total_pnl_gross(acc::Account) = sum(map(get_pnl_gross, acc.closed_positions))

@inline count_winners_net(acc::Account) = count(map(x -> get_pnl_net(x) > 0.0, acc.closed_positions))
@inline count_winners_gross(acc::Account) = count(map(x -> get_pnl_gross(x) > 0.0, acc.closed_positions))

# # Dates.func(nbbo.dt) accessor shortcuts, e.g. year(nbbo), day(nbbo), hour(nbbo)
# for func in (:year, :month, :day, :hour, :minute, :second, :millisecond, :microsecond, :nanosecond)
#     name = string(func)
#     @eval begin
#         $func(ba::BidAsk)::Int64 = Dates.$func(ba.dt)
#     end
# end
