import Base: *, sign
using Dates
using Printf
using Crayons


const Price = Float64           # quote bid/ask, traded price
const Return = Price            # same as price
const Volume = Float64          # trade volume / number of shares

@enum TradeDir::Int16 NullDir = 0 Long = 1 Short = -1

@inline sign(x::TradeDir) = Volume(Int16(x))
@inline trade_dir(volume) = volume > 0 ? Long : ((volume < 0) ? Short : NullDir)

@inline *(x::Volume, dir::TradeDir) = Volume(x * sign(dir))
@inline *(dir::TradeDir, x::Volume) = Volume(x * sign(dir))

# ----------------------------------------------------------

struct Instrument{T}
    index::Int64                # unique index for each instrument starting from 1 (used for array indexing and hashing)
    symbol::String
    data::T
    __hash::UInt64
    Instrument(index, symbol) = new{Nothing}(index, symbol, nothing, convert(UInt64, index))
    Instrument(index, symbol, data::T) where {T} = new{T}(index, symbol, data, convert(UInt64, index))
end

Base.hash(inst::Instrument) = inst.__hash  # custom hash for better performance

# ----------------------------------------------------------

struct BidAsk
    dt::DateTime
    bid::Price
    ask::Price
    BidAsk() = new(DateTime(0), Price(0.0), Price(0.0))
    BidAsk(dt::DateTime, bid::Price, ask::Price) = new(dt, bid, ask)
end

# ----------------------------------------------------------

mutable struct OrderBook
    index::Int64                # unique index for each position starting from 1 (used for array indexing and hashing)
    inst::Instrument
    bba::BidAsk
end

# ----------------------------------------------------------

struct MarketData{I}
    instruments::Vector{Instrument{I}}
    order_books::Vector{OrderBook}
    MarketData(instruments::Vector{Instrument{I}}) where {I} = new{I}(instruments, [OrderBook(i.index, i, BidAsk()) for i in instruments])
end

# ----------------------------------------------------------

mutable struct OrderExecution
    dt::DateTime
    quantity::Volume            # negative = short selling
    price::Price                # price at which the order was filled
    pos_quantity::Volume        # quantity of the existing position
    pos_avg_price::Price        # average price of the existing position
    # weight::Price               # weight of the order after it got executed (relative to equity)
    realized_pnl::Price         # realized P&L from exposure reduction (covering)
    realized_quantity::Volume   # quantity of the existing position that was covered by the order
end

# ----------------------------------------------------------

struct Order
    inst::Instrument
    quantity::Volume            # negative = short selling
    dt::DateTime
    execution::OrderExecution
    Order(inst::Instrument, quantity::Volume, dt::DateTime) =
        new(inst, quantity, dt, OrderExecution(DateTime(0), 0, 0, 0, 0, 0, 0))
end

# ----------------------------------------------------------

mutable struct Position
    index::Int64                # unique index for each position starting from 1 (used for array indexing and hashing)
    inst::Instrument
    quantity::Volume            # negative = short selling
    orders_history::Vector{Order}
    avg_price::Price
    pnl::Price
end

# ----------------------------------------------------------

mutable struct Account
    positions::Vector{Position} # same size/indexing as MarketData.instruments and MarketData.order_books
    orders_history::Vector{Order}
    initial_balance::Price
    balance::Price
    equity::Price
    function Account(instruments, initial_balance::Price)
        new(
            [Position(i.index, i, 0.0, Vector{Order}(), 0.0, 0.0) for i in instruments],
            Vector{Order}(),
            initial_balance,
            initial_balance,
            initial_balance)
    end
end

# ----------------------------------------------------------
