import Base: *, sign
import PrettyTables
using Printf
using Dates

const Price = Float64    # quote bid/ask, traded price
const Volume = Float64   # trade volume / number of shares
const Return = Float64

@enum TradeMode::Int16 LongShort=0 LongOnly=1 ShortOnly=-1
@enum TradeDir::Int16 Undefined=0 Long=1 Short=-1

@inline TradeDir(x::Volume) = TradeDir(Int16(sign(x)))
@inline sign(x::TradeDir) = Int64(x)

@inline *(x::Volume, dir::TradeDir) = Volume(x * sign(dir))
@inline *(dir::TradeDir, x::Volume) = Volume(x * sign(dir))

# ----------------------------------------------------------

struct Instrument
    id      ::String
    __hash  ::UInt64  # precomputed/cached hash
    Instrument(id) = new(id, hash(id))
end

# custom hash (cached hash)
Base.hash(inst::Instrument) = inst.__hash

# console output when printing object
function Base.show(io::IO, inst::Instrument)
    print(io, "[Instrument] id=$(inst.id)")
end

# ----------------------------------------------------------

struct BidAsk
    dt      ::DateTime
    bid     ::Price
    ask     ::Price
    BidAsk() = new(DateTime(0), Price(0.0), Price(0.0))
    BidAsk(dt::DateTime, bid::Price, ask::Price) = new(dt, bid, ask)
end

# console output when printing object
function Base.show(io::IO, ba::BidAsk)
    print(io, "[BidAsk] dt=$(ba.dt)  bid=$(ba.bid)  ask=$(ba.ask)")
end

# ----------------------------------------------------------

@enum CloseReason::Int64 Unspecified=0 StopLoss=1 TakeProfit=2

mutable struct Position
    inst            ::Instrument
    size            ::Volume  # negative = short selling
    dir             ::TradeDir
    open_quotes     ::BidAsk
    open_dt         ::DateTime
    open_price      ::Price
    last_quotes     ::BidAsk
    last_dt         ::DateTime
    last_price      ::Price
    stop_loss       ::Price
    take_profit     ::Price
    close_reason    ::CloseReason
    pnl             ::Price
end

# console output when printing object
function Base.show(io::IO, pos::Position)
    size_str = @sprintf("%.2f", pos.size)
    if sign(pos.size) != -1
        size_str = " " * size_str
    end
    pnl_str = @sprintf("%+.2f", pos.pnl)
    print(io, "[Position] $size_str $(pos.inst.id) "*
        "open=($(Dates.format(pos.open_dt, "yyyy-mm-dd HH:MM:SS")), $(@sprintf("%.2f", pos.open_price)))  "*
        "last=($(Dates.format(pos.last_dt, "yyyy-mm-dd HH:MM:SS")), $(@sprintf("%.2f", pos.last_price)))  "*
        "pnl=$pnl_str  stop_loss=$(@sprintf("%.2f", pos.stop_loss))  take_profit=$(@sprintf("%.2f", pos.take_profit))  "*
        "close_reason=$(pos.close_reason)")
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
    OpenOrder(inst::Instrument, size::Volume, dir::TradeDir) = new(inst, size, dir, NaN, NaN)
    OpenOrder(inst::Instrument, size::Volume, dir::TradeDir, stop_loss::Price, take_profit::Price) = new(inst, size, dir, stop_loss, take_profit)
end

# console output when printing object
function Base.show(io::IO, order::OpenOrder)
    print(io, "[OpenOrder] $(order.size) $(order.inst.id)  stop_loss=$(@sprintf("%.2f", order.stop_loss))  take_profit=$(@sprintf("%.2f", order.take_profit))")
end

# ----------------------------------------------------------

struct CloseOrder <: Order
    pos             ::Position
    close_reason    ::CloseReason
    CloseOrder(pos::Position) = new(pos, Unspecified::CloseReason)
    CloseOrder(pos::Position, close_reason::CloseReason) = new(pos, close_reason)
end

# console output when printing object
function Base.show(io::IO, order::CloseOrder)
    print(io, "[CloseOrder] $(order.pos)  $(order.close_reason)")
end

# ----------------------------------------------------------

struct CloseAllOrder <: Order
end

# console output when printing object
function Base.show(io::IO, order::CloseAllOrder)
    print(io, "[CloseAllOrder]")
end

# ----------------------------------------------------------

# abstract type OrderExecutor
# end

# ----------------------------------------------------------

mutable struct Account
    open_positions      ::Vector{Position}
    closed_positions    ::Vector{Position}
    balance             ::Price
    equity              ::Price

    Account(balance::Price) = new(
        Vector{Position}(),
        Vector{Position}(),
        balance,
        balance)
end

# console output when printing object
function Base.show(io::IO, acc::Account; volume_digits=1, price_digits=2, kwargs...)
    x, y = displaysize(io)
    title = " ACCOUNT SUMMARY "
    border_char = '━'
    eq_width = y - length(title)
    eqs = border_char^(floor(Int64, eq_width/2))
    println(io, "")
    println(io, eqs * title * eqs)
    println(io, "")
    println(io, " ", "Open positions:     $(length(acc.open_positions))")
    print_positions(io, acc.open_positions; kwargs...)
    println(io, "")

    println(io, "")
    println(io, " ", "Closed positions:   $(length(acc.closed_positions))")
    print_positions(io, acc.closed_positions; kwargs...)
    println(io, "")

    println(io, " ", "Balance:            $(@sprintf("%.2f", acc.balance))\n")
    println(io, " ", "Equity:             $(@sprintf("%.2f", acc.equity))\n")
    println(io, border_char^y)
    println(io, "")
end


function print_positions(positions::Vector{Position}; max_print=25, volume_digits=1, price_digits=2, kwargs...)
    print_positions(stdout, positions::Vector{Position}; max_print, volume_digits, price_digits, kwargs...)
end

function print_positions(io::IO, positions::Vector{Position}; max_print=25, volume_digits=1, price_digits=2)
    columns = ["Inst." "Volume" "Open time" "Open price" "Last quote" "Last price" "P&L" "Stop loss" "Take profit" "Close reason"]
    df = dateformat"yyyy-mm-dd HH:MM:SS"
    formatter = (v,i,j) -> begin
        o = v
        if j == 2
            # Volume
            o = round(v; digits=volume_digits)
        elseif j == 4 || j == 6 || j == 7 || j == 8 || j == 9
            # Open price / Last price / P&L / Stop loss / Take profit
            if isnan(v)
                o = "—"
            else
                o = round(v; digits=price_digits)
            end
        elseif j == 3 || j == 5
            # Open time / Last quote
            o = Dates.format(v, df)
        end
        o
    end

    n = length(positions)
    if n > 0
        data = map(pos -> [pos.inst.id pos.size pos.open_dt get_open_price(pos) pos.last_dt get_close_price(pos) pos.pnl pos.stop_loss pos.take_profit pos.close_reason], positions)
        data = reduce(vcat, data)
        if !isnan(max_print) && size(data, 1) > max_print
            PrettyTables.pretty_table(io, data[1:max_print, :], columns; formatters=formatter)
            println(io, " [...] $(n - max_print) more positions")
        else
            PrettyTables.pretty_table(io, data, columns; formatters=formatter)
        end
    end
end

# ----------------------------------------------------------

mutable struct PeriodicValues
    period          ::Period
    values          ::Vector{Tuple{DateTime, Float64}}
    last_dt         ::DateTime
    last_value      ::Float64
    PeriodicValues(period::Period) = new(
        period,
        Vector{Tuple{DateTime, Float64}}(),
        DateTime(0),
        NaN)
end

# ----------------------------------------------------------

# mutable struct DrawdownCollector
#     period::Period
#     values::Vector{Tuple{DateTime, Float64}}
#     last_dt::DateTime
#     max_equity::Float64
#     DrawdownCollector(period) = new(
#         period,
#         Vector{Tuple{DateTime, Float64}}(),
#         DateTime(0),
#         NaN)
# end

# ----------------------------------------------------------

# mutable struct PeriodicValuesCollector
#     period::Period
#     values::Vector{Tuple{DateTime, Float64}}
#     last_dt::DateTime
#     PeriodicValuesCollector(period) = new(
#         period,
#         Vector{Tuple{DateTime, Float64}}(),
#         DateTime(0))
# end

# ----------------------------------------------------------

# @inline function drawdown_collect!(dc::DrawdownCollector, dt::DateTime, equity::Float64)
#     if isnan(dc.max_equity)
#         # initialize max equity value
#         dc.max_equity = equity
#     end

#     # update max equity value
#     dc.max_equity = max(dc.max_equity, equity)

#     if (dt - dc.last_dt) >= dc.period
#         drawdown = min(0.0, equity - dc.max_equity)
#         push!(dc.values, (dt, drawdown))
#         dc.last_dt = dt
#     end

#     return
# end

# @inline function pv_collect!(dc::PeriodicValuesCollector, dt::DateTime, value::Float64)
#     if (dt - dc.last_dt) >= dc.period
#         push!(dc.values, (dt, value))
#         dc.last_dt = dt
#     end
#     return
# end

# ----------------------------------------------------------
