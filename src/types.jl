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

struct Instrument{I}
    index::Int64                # unique index for each instrument starting from 1 (used for array indexing and hashing)
    symbol::String
    data::I
    __hash::UInt64
    Instrument(index, symbol) = new{Nothing}(index, symbol, nothing, convert(UInt64, index))
    Instrument(index, symbol, data::I) where {I} = new{I}(index, symbol, data, convert(UInt64, index))
end

Base.hash(inst::Instrument{I}) where {I} = inst.__hash  # custom hash for better performance

# ----------------------------------------------------------

struct BidAsk
    dt::DateTime
    bid::Price
    ask::Price
    BidAsk() = new(DateTime(0), Price(0.0), Price(0.0))
    BidAsk(dt::DateTime, bid::Price, ask::Price) = new(dt, bid, ask)
end

# ----------------------------------------------------------

# TODO: Immutable

mutable struct OrderBook{I}
    index::Int64                # unique index for each position starting from 1 (used for array indexing and hashing)
    inst::Instrument{I}
    bba::BidAsk
end

# ----------------------------------------------------------

struct MarketData{I}
    instruments::Vector{Instrument{I}}
    order_books::Vector{OrderBook{I}}
    MarketData(instruments::Vector{Instrument{I}}) where {I} = new{I}(instruments, [OrderBook{I}(i.index, i, BidAsk()) for i in instruments])
end

# ----------------------------------------------------------

struct Order{O,I}
    inst::Instrument{I}
    quantity::Volume            # negative = short selling
    dt::DateTime
    data::O
    Order(inst::Instrument{I}, quantity::Volume, dt::DateTime, data::O) where {O,I} =
        new{O,I}(inst, quantity, dt, data)
    Order(inst::Instrument{I}, quantity::Volume, dt::DateTime) where {I} =
        new{Nothing,I}(inst, quantity, dt, nothing)
end

# ----------------------------------------------------------

struct Execution
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

struct Transaction{O,I}
    order::Order{O,I}
    execution::Execution
    Transaction(order::Order{O,I}, execution::Execution) where {O,I} =
        new{O,I}(order, execution)
end

# ----------------------------------------------------------

mutable struct Position{O,I}
    index::Int64                # unique index for each position starting from 1 (used for array indexing and hashing)
    inst::Instrument{I}
    quantity::Volume            # negative = short selling
    transactions::Vector{Transaction{O}}
    avg_price::Price
    pnl::Price
    Position{O}(index, inst::Instrument{I}, quantity, transactions, avg_price, pnl) where {O,I} =
        new{O,I}(index, inst, quantity, transactions, avg_price, pnl)
    Position(index, inst::Instrument{I}, quantity, transactions, avg_price, pnl) where {I} =
        new{Nothing,I}(index, inst, quantity, transactions, avg_price, pnl)
end

# ----------------------------------------------------------

mutable struct Account{O,I}
    positions::Vector{Position{O,I}} # same size/indexing as MarketData.instruments and MarketData.order_books
    transactions::Vector{Transaction{O,I}}
    initial_balance::Price
    balance::Price
    equity::Price
    function Account{O}(instruments::Vector{Instrument{I}}, initial_balance::Price) where {O,I}
        new{O,I}(
            [Position{O}(i.index, i, 0.0, Vector{Transaction{O,I}}(), 0.0, 0.0) for i in instruments],
            Vector{Transaction{O,I}}(),
            initial_balance,
            initial_balance,
            initial_balance)
    end
    function Account(instruments::Vector{Instrument{I}}, initial_balance::Price) where {I}
        Account{Nothing}(instruments, initial_balance)
    end
end

# ----------------------------------------------------------
