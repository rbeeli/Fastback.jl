import Base: *, sign
using Dates
using Printf
using Crayons


const Price = Float64    # quote bid/ask, traded price
const Volume = Float64   # trade volume / number of shares
const Return = Price     # same as price

@enum TradeDir::Int16 NullDir=0 Long=1 Short=-1

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

function Base.show(io::IO, inst::Instrument)
    data_str = isnothing(inst.data) ? "" : "  data=<object>"
    print(io, "[Instrument] symbol=$(inst.symbol)$data_str")
end

# ----------------------------------------------------------

struct BidAsk
    dt      ::DateTime
    bid     ::Price
    ask     ::Price
    BidAsk() = new(DateTime(0), Price(0.0), Price(0.0))
    BidAsk(dt::DateTime, bid::Price, ask::Price) = new(dt, bid, ask)
end

function Base.show(io::IO, ba::BidAsk)
    print(io, "[BidAsk] dt=$(ba.dt)  bid=$(ba.bid)  ask=$(ba.ask)")
end

# ----------------------------------------------------------

@enum CloseReason::Int64 NullReason=0 StopLoss=1 TakeProfit=2

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

function Base.show(io::IO, pos::Position)
    size_str = @sprintf("%.2f", pos.size)
    if sign(pos.size) != -1
        size_str = " " * size_str
    end
    pnl_str = @sprintf("%+.2f", pos.pnl)
    data_str = isnothing(pos.data) ? "nothing" : "<object>"
    print(io, "[Position] $(pos.inst.symbol) $(pos.dir) $size_str  "*
        "open=($(Dates.format(pos.open_dt, "yyyy-mm-dd HH:MM:SS")), $(@sprintf("%.2f", pos.open_price)))  "*
        "last=($(Dates.format(pos.last_dt, "yyyy-mm-dd HH:MM:SS")), $(@sprintf("%.2f", pos.last_price)))  "*
        "pnl=$pnl_str  stop_loss=$(@sprintf("%.2f", pos.stop_loss))  take_profit=$(@sprintf("%.2f", pos.take_profit))  "*
        "close_reason=$(pos.close_reason)  data=$data_str")
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

function Base.show(io::IO, order::OpenOrder)
    print(io, "[OpenOrder] $(order.inst.symbol) $(order.size) $(order.dir)  stop_loss=$(@sprintf("%.2f", order.stop_loss))  take_profit=$(@sprintf("%.2f", order.take_profit))")
end

# ----------------------------------------------------------

struct CloseOrder <: Order
    pos             ::Position
    close_reason    ::CloseReason
    CloseOrder(pos::Position) = new(pos, NullReason::CloseReason)
    CloseOrder(pos::Position, close_reason::CloseReason) = new(pos, close_reason)
end

function Base.show(io::IO, order::CloseOrder)
    print(io, "[CloseOrder] $(order.pos)  $(order.close_reason)")
end

# ----------------------------------------------------------

# struct CloseAllOrder <: Order
# end

# function Base.show(io::IO, order::CloseAllOrder)
#     print(io, "[CloseAllOrder]")
# end

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

function Base.show(io::IO, acc::Account; volume_digits=1, price_digits=2, kwargs...)
    # volume_digits and price_digits are passed to print_positions(...)
    display_width = displaysize()[2]
    
    function get_color(val)
        if val >= 0
            return val == 0 ? crayon"rgb(128,128,128)" : crayon"green"
        end
        return crayon"red"
    end

    title = " ACCOUNT SUMMARY "
    title_line = '━'^(floor(Int64, (display_width - length(title))/2))
    println(io, "")
    println(io, title_line * title * title_line)
    println(io, " ", "Initial balance:    $(@sprintf("%.2f", acc.initial_balance))")
    print(io,   " ", "Balance:            $(@sprintf("%.2f", acc.balance))")
    print(io, " (")
    print(io, get_color(balance_ret(acc)), "$(@sprintf("%+.2f", balance_ret(acc)*100))%", Crayon(reset=true))
    print(io, ")\n")
    print(io, " ", "Equity:             $(@sprintf("%.2f", acc.equity))")
    print(io, " (")
    print(io, get_color(equity_ret(acc)), "$(@sprintf("%+.2f", equity_ret(acc)*100))%", Crayon(reset=true))
    print(io, ")\n")
    println(io, "")
    println(io, " ", "Open positions:     $(length(acc.open_positions))")
    print_positions(io, acc.open_positions; kwargs...)
    println(io, "")
    println(io, " ", "Closed positions:   $(length(acc.closed_positions))")
    print_positions(io, acc.closed_positions; kwargs...)
    println(io, '━'^display_width)
    println(io, "")
end

# ----------------------------------------------------------
