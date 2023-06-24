# ------------------------
# BidAsk
# ------------------------

@inline midprice(ba::BidAsk) = (ba.bid + ba.ask) / 2.0
@inline midprice(bid::Price, ask::Price) = (bid + ask) / 2.0

@inline spread(ba::BidAsk) = (ba.ask - ba.bid)
@inline spread(bid::Price, ask::Price) = (ask - bid)


# ------------------------
# TradeDir
# ------------------------

@inline is_long(dir::TradeDir) = dir === Long
@inline is_short(dir::TradeDir) = dir === Short
@inline opposite_dir(dir::TradeDir) = dir === Long ? Short : (dir === Short ? Long : NullDir)


# ------------------------
# Position
# ------------------------

@inline is_long(pos::Position) = pos.quantity > 0
@inline is_short(pos::Position) = pos.quantity < 0
@inline trade_dir(pos::Position) = trade_dir(pos.quantity)


# ------------------------
# Order
# ------------------------

@inline trade_dir(order::Order) = trade_dir(order.quantity)
