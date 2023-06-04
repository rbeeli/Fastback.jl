# ------------------------
# BidAsk
# ------------------------

@inline midprice(ba::BidAsk) = (ba.bid + ba.ask) / 2.0
@inline midprice(bid::Price, ask::Price) = (bid + ask) / 2.0

@inline spread(ba::BidAsk) = (ba.ask - ba.bid)
@inline spread(bid::Price, ask::Price) = (ask - bid)

@inline open_price(dir::TradeDir, ba::BidAsk) = is_long(dir) ? ba.ask : (is_short(dir) ? ba.bid : NaN)
@inline close_price(dir::TradeDir, ba::BidAsk) = is_long(dir) ? ba.bid : (is_short(dir) ? ba.ask : NaN)


# ------------------------
# TradeDir
# ------------------------

@inline is_long(dir::TradeDir) = dir === Long
@inline is_short(dir::TradeDir) = dir === Short
@inline function opposite_dir(dir::TradeDir)
    if dir === Long
        return Short
    elseif dir === Short
        return Long
    else
        return NullDir
    end
end


# ------------------------
# Position
# ------------------------

@inline is_long(pos::Position) = pos.dir === Long
@inline is_short(pos::Position) = pos.dir === Short

# size negative for shorts, thus works for both long and short
@inline pnl_net(pos::Position) = pos.size * (pos.last_price - pos.open_price)
@inline pnl_gross(pos::Position) = pos.size * (midprice(pos.last_quote) - midprice(pos.open_quote))

# size negative for shorts, thus works for both long and short
@inline return_net(pos::Position) = pos.dir * (pos.last_price - pos.open_price) / pos.open_price
@inline return_gross(pos::Position) = pos.dir * ((midprice(pos.last_quote) - midprice(pos.open_quote)) / midprice(pos.open_quote))


# ------------------------
# Account
# ------------------------

@inline balance_ret(acc::Account) = acc.balance / acc.initial_balance - 1.0
@inline equity_ret(acc::Account) = acc.equity / acc.initial_balance - 1.0

@inline has_open_positions(acc::Account) = length(acc.open_positions) > 0
@inline has_closed_positions(acc::Account) = length(acc.closed_positions) > 0

function has_open_position_with_dir(acc::Account, inst::Instrument, dir::TradeDir)
    for pos in acc.open_positions
        if pos.inst == inst && pos.dir == dir
            return true
        end
    end
    false
end

# account total return based on initial balance and current equity
@inline total_return(acc::Account) = acc.equity / acc.initial_balance - 1.0

@inline total_pnl_net(acc::Account) = sum(map(pnl_net, acc.closed_positions))
@inline total_pnl_gross(acc::Account) = sum(map(pnl_gross, acc.closed_positions))

@inline count_winners_net(acc::Account) = count(map(x -> pnl_net(x) > 0.0, acc.closed_positions))
@inline count_winners_gross(acc::Account) = count(map(x -> pnl_gross(x) > 0.0, acc.closed_positions))

# # Dates.func(nbbo.dt) accessor shortcuts, e.g. year(nbbo), day(nbbo), hour(nbbo)
# for func in (:year, :month, :day, :hour, :minute, :second, :millisecond, :microsecond, :nanosecond)
#     name = string(func)
#     @eval begin
#         $func(ba::BidAsk)::Int64 = Dates.$func(ba.dt)
#     end
# end
