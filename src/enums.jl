import Base: *, sign
using EnumX

@enumx TradeDir::Int8 Null = 0 Long = 1 Short = -1

@inline sign(x::TradeDir.T) = Quantity(Int8(x))
@inline is_long(dir::TradeDir.T) = dir === TradeDir.Long
@inline is_short(dir::TradeDir.T) = dir === TradeDir.Short
@inline opposite_dir(dir::TradeDir.T) = dir === TradeDir.Long ? TradeDir.Short : (dir === TradeDir.Short ? TradeDir.Long : TradeDir.Null)
@inline trade_dir(volume::T) where {T<:Number} = volume > 0 ? Long : ((volume < 0) ? TradeDir.Short : TradeDir.Null)

@inline *(x::TQuantity, dir::TradeDir.T) where {TQuantity<:Number} = TQuantity(x * sign(dir))
@inline *(dir::TradeDir.T, x::TQuantity) where {TQuantity<:Number} = TQuantity(x * sign(dir))
