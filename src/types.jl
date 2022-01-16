import Base: *, sign
using Dates

const Price = Float64    # quote bid/ask, traded price
const Volume = Float64   # trade volume / number of shares
const Return = Price     # same as price

@enum TradeDir::Int16 Undefined=0 Long=1 Short=-1

@inline sign(x::TradeDir) = Int64(x)

@inline *(x::Volume, dir::TradeDir) = Volume(x * sign(dir))
@inline *(dir::TradeDir, x::Volume) = Volume(x * sign(dir))

# ----------------------------------------------------------

struct Instrument
    symbol  ::String
    data    ::Any       # user-defined data field for instrument
    __hash  ::UInt64    # precomputed/cached hash
    Instrument(symbol; data::Any=nothing) = new(symbol, data, hash(symbol))
end

# custom hash (cached hash)
Base.hash(inst::Instrument) = inst.__hash

# ----------------------------------------------------------

struct BidAsk
    dt      ::DateTime
    bid     ::Price
    ask     ::Price
    BidAsk() = new(DateTime(0), Price(0.0), Price(0.0))
    BidAsk(dt::DateTime, bid::Price, ask::Price) = new(dt, bid, ask)
end

# ----------------------------------------------------------

@enum CloseReason::Int64 Unspecified=0 StopLoss=1 TakeProfit=2

mutable struct Position
    inst            ::Instrument
    size            ::Volume        # negative = short selling
    dir             ::TradeDir
    open_quote      ::BidAsk
    open_dt         ::DateTime
    open_price      ::Price
    last_quote      ::BidAsk
    last_dt         ::DateTime
    last_price      ::Price
    stop_loss       ::Price
    take_profit     ::Price
    close_reason    ::CloseReason
    pnl             ::Price
    data            ::Any           # user-defined data field for position instance
end

# ----------------------------------------------------------

abstract type Order
end

# ----------------------------------------------------------

struct OpenOrder <: Order
    inst            ::Instrument
    size            ::Volume
    dir             ::TradeDir
    stop_loss       ::Price
    take_profit     ::Price
    data            ::Any           # user-defined data field for position instance
    OpenOrder(
        inst::Instrument,
        size::Volume,
        dir::TradeDir;
        stop_loss::Price=NaN,
        take_profit::Price=NaN,
        data::Any=nothing) = new(inst, size, dir, stop_loss, take_profit, data)
end

# ----------------------------------------------------------

struct CloseOrder <: Order
    pos             ::Position
    close_reason    ::CloseReason
    CloseOrder(pos::Position) = new(pos, Unspecified::CloseReason)
    CloseOrder(pos::Position, close_reason::CloseReason) = new(pos, close_reason)
end

# ----------------------------------------------------------

struct CloseAllOrder <: Order
end

# ----------------------------------------------------------

mutable struct Account
    open_positions      ::Vector{Position}
    closed_positions    ::Vector{Position}
    initial_balance     ::Price
    balance             ::Price
    equity              ::Price
    data                ::Any           # user-defined data field for account instance

    Account(initial_balance::Price; data::Any=missing) = new(
        Vector{Position}(),
        Vector{Position}(),
        initial_balance,
        initial_balance,
        initial_balance,
        data)
end

# ----------------------------------------------------------
