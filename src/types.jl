import Base: *, sign
using Dates
using Printf
using Crayons
using EnumX

const Price = Float64           # quote bid/ask, traded price
const Return = Float64          # same as price
const Volume = Float64          # trade volume / number of shares

@enumx TradeDir::Int8 Null = 0 Long = 1 Short = -1

@inline sign(x::TradeDir.T) = Volume(Int8(x))
@inline trade_dir(volume) = volume > 0 ? Long : ((volume < 0) ? TradeDir.Short : TradeDir.Null)

@inline *(x::Volume, dir::TradeDir.T) = Volume(x * sign(dir))
@inline *(dir::TradeDir.T, x::Volume) = Volume(x * sign(dir))

# ----------------------------------------------------------

struct Instrument{I}
    index::Int64                # unique index for each instrument starting from 1 (used for array indexing and hashing)
    symbol::String
    data::I
    __hash::UInt64

    function Instrument(index, symbol)
        new{Nothing}(index, symbol, nothing, convert(UInt64, index))
    end

    function Instrument(index, symbol, data::I) where {I}
        new{I}(index, symbol, data, convert(UInt64, index))
    end
end

Base.hash(inst::Instrument{I}) where {I} = inst.__hash  # custom hash for better performance

# ----------------------------------------------------------

struct Order{O,I}
    inst::Instrument{I}
    quantity::Volume            # negative = short selling
    dt::DateTime
    data::O

    function Order(inst::Instrument{I}, quantity::Volume, dt::DateTime; data=nothing) where {I}
        new{typeof(data),I}(inst, quantity, dt, nothing)
    end
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

    function Transaction(order::Order{O,I}, execution::Execution) where {O,I}
        new{O,I}(order, execution)
    end
end

# ----------------------------------------------------------

mutable struct Position{O,I}
    index::Int64                # unique index for each position starting from 1 (used for array indexing and hashing)
    inst::Instrument{I}
    quantity::Volume            # negative = short selling
    transactions::Vector{Transaction{O}}
    avg_price::Price
    pnl::Price
    __hash::UInt64

    function Position{O}(index, inst::Instrument{I}, quantity, transactions, avg_price, pnl) where {O,I}
        new{O,I}(index, inst, quantity, transactions, avg_price, pnl, convert(UInt64, index))
    end

    function Position(index, inst::Instrument{I}, quantity, transactions, avg_price, pnl) where {I}
        new{Nothing,I}(index, inst, quantity, transactions, avg_price, pnl, convert(UInt64, index))
    end
end

Base.hash(pos::Position{O,I}) where {O,I} = pos.__hash  # custom hash for better performance

# ----------------------------------------------------------

mutable struct Account{O,I}
    positions::Vector{Position{O,I}}
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
