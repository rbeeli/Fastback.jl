import Base: *, sign
using EnumX

@enumx TradeDir::Int8 Null = 0 Buy = 1 Sell = -1
@enumx SettlementStyle::Int8 Asset = 1 VariationMargin = 2
@enumx MarginMode::Int8 None = 0 PercentNotional = 1 FixedPerContract = 2
@enumx MarginingStyle::Int8 PerCurrency = 1 BaseCurrency = 2
@enumx ContractKind::Int8 Spot = 1 Perpetual = 2 Future = 3
@enumx AccountMode::Int8 Cash = 1 Margin = 2
@enumx OrderRejectReason::Int8 None = 0 InstrumentNotAllowed = 1 InsufficientCash = 2 ShortNotAllowed = 3 InsufficientInitialMargin = 4
@enumx TradeReason::Int8 Normal = 0 Liquidation = 1 Expiry = 2 Roll = 3

@inline sign(x::TradeDir.T) = Quantity(Int8(x))

"""
Return `true` if the trade direction is long (buy).
"""
@inline is_long(dir::TradeDir.T) = dir == TradeDir.Buy

"""
Return `true` if the trade direction is short (sell).
"""
@inline is_short(dir::TradeDir.T) = dir == TradeDir.Sell

"""
Return the opposite trade direction (buy ↔ sell).
"""
@inline function opposite_dir(dir::TradeDir.T)
    dir == TradeDir.Buy ? TradeDir.Sell : (dir == TradeDir.Sell ? TradeDir.Buy : TradeDir.Null)
end

"""
Infer trade direction from a signed quantity.
"""
@inline function trade_dir(volume::T) where {T<:Number}
    volume > 0 ? TradeDir.Buy : (volume < 0 ? TradeDir.Sell : TradeDir.Null)
end

@inline *(qty::TQuantity, dir::TradeDir.T) where {TQuantity<:Number} = TQuantity(qty * sign(dir))
@inline *(dir::TradeDir.T, qty::TQuantity) where {TQuantity<:Number} = TQuantity(qty * sign(dir))
