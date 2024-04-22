# TradeDir
@inline is_long(dir::TradeDir.T) = dir === TradeDir.Long
@inline is_short(dir::TradeDir.T) = dir === TradeDir.Short
@inline opposite_dir(dir::TradeDir.T) = dir === TradeDir.Long ? TradeDir.Short : (dir === TradeDir.Short ? TradeDir.Long : TradeDir.Null)

# Position
@inline is_long(pos::Position) = pos.quantity > 0
@inline is_short(pos::Position) = pos.quantity < 0
@inline trade_dir(pos::Position) = trade_dir(pos.quantity)

# Order
@inline trade_dir(order::Order) = trade_dir(order.quantity)
