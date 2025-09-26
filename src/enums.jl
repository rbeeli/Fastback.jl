import Base: *, sign
using EnumX

@enumx TradeDir::Int8 Null = 0 Buy = 1 Sell = -1

@inline sign(x::TradeDir.T) = Quantity(Int8(x))
@inline is_long(dir::TradeDir.T) = dir == TradeDir.Buy
@inline is_short(dir::TradeDir.T) = dir == TradeDir.Sell

@inline function opposite_dir(dir::TradeDir.T)
    dir == TradeDir.Buy ? TradeDir.Sell : (dir == TradeDir.Sell ? TradeDir.Buy : TradeDir.Null)
end

@inline function trade_dir(volume::T) where {T<:Number}
    volume > 0 ? TradeDir.Buy : (volume < 0 ? TradeDir.Sell : TradeDir.Null)
end

@inline *(qty::TQuantity, dir::TradeDir.T) where {TQuantity<:Number} = TQuantity(qty * sign(dir))
@inline *(dir::TradeDir.T, qty::TQuantity) where {TQuantity<:Number} = TQuantity(qty * sign(dir))
