import Base: *, sign
using Printf
using Dates

const Price = Float64    # stock quote bid/ask, traded price
const Volume = Float64   # trade volume / number of shares
const Return = Float64

@enum TradeMode::Int16 LongShort=0 LongOnly=1 ShortOnly=-1
@enum TradeDir::Int16 Undefined=0 Long=1 Short=-1

@inline TradeDir(x::Volume) = TradeDir(Int16(sign(x)))
@inline sign(x::TradeDir) = Int64(x)

@inline *(x::Float64, dir::TradeDir) = Volume(x * sign(dir))
@inline *(dir::TradeDir, x::Float64) = Volume(x * sign(dir))
@inline *(x::Int64, dir::TradeDir) = Volume(x * sign(dir))
@inline *(dir::TradeDir, x::Int64) = Volume(x * sign(dir))
@inline *(x::Volume, dir::TradeDir) = Volume(x * sign(dir))
@inline *(dir::TradeDir, x::Volume) = Volume(x * sign(dir))

# ----------------------------------------------------------

struct Security
    ticker      ::String
    __hash      ::UInt64  # precomputed/cached hash
    Security(ticker) = new(ticker, hash(ticker))
end

# custom hash (cached hash)
Base.hash(sec::Security) = sec.__hash

# console output when printing object
function Base.show(io::IO, sec::Security)
    print(io, "ticker=$(sec.ticker)")
end

# ----------------------------------------------------------

struct BidAsk
    dt      ::DateTime
    bid     ::Price
    ask     ::Price
    BidAsk() = new(DateTime(0), Price(0.0), Price(0.0))
    BidAsk(dt::DateTime, bid::Price, ask::Price) = new(dt, bid, ask)
end

# Dates.func(nbbo.dt) accessor shortcuts, e.g. year(nbbo), day(nbbo), hour(nbbo)
for func in (:year, :month, :day, :hour, :minute, :second, :millisecond, :microsecond, :nanosecond)
    name = string(func)
    @eval begin
        $func(ba::BidAsk)::Int64 = Dates.$func(ba.dt)
    end
end

# console output when printing object
function Base.show(io::IO, ba::BidAsk)
    print(io, "dt=$(ba.dt)  bid=$(ba.bid)  ask=$(ba.ask)")
end

# ----------------------------------------------------------

@enum CloseReason::Int64 Unspecified=0 StopLoss=1 TakeProfit=2

mutable struct Position
    sec             ::Security
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
    print(io, "<Position> [$(pos.sec.ticker)] size=$size_str  "*
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
    sec             ::Security
    size            ::Volume
    dir             ::TradeDir
    stop_loss       ::Price
    take_profit     ::Price
    OpenOrder(sec::Security, size::Volume, dir::TradeDir) = new(sec, size, dir, NaN, NaN)
    OpenOrder(sec::Security, size::Volume, dir::TradeDir, stop_loss::Price, take_profit::Price) = new(sec, size, dir, stop_loss, take_profit)
end

# console output when printing object
function Base.show(io::IO, order::OpenOrder)
    print(io, "<OpenOrder> [$(order.sec.ticker)]  size=$(order.size)  stop_loss=$(@sprintf("%.2f", order.stop_loss))  take_profit=$(@sprintf("%.2f", order.take_profit))")
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
    print(io, "<CloseOrder> $(order.pos)  $(order.close_reason)")
end

# ----------------------------------------------------------

struct CloseAllOrder <: Order
end

# console output when printing object
function Base.show(io::IO, order::CloseAllOrder)
    print(io, "<CloseAllOrder>")
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
function Base.show(io::IO, acc::Account)
    max_print_items = 10
    lvl1_indent = "  "
    lvl2_indent = "     "

    println(io, "")

    # println(io, lvl1_indent, "Place orders:       $(acc.place_orders_count)")
    # i = 0
    # for (sec, orders) in acc.place_orders
    #     for o in orders
    #         println(io, lvl2_indent, o)
    #         i += 1
    #         if i == max_print_items
    #             break
    #         end
    #     end
    # end
    # if i < acc.place_orders_count
    #     println(io, lvl2_indent, "[...] $(acc.place_orders_count - i) more items")
    # end
    # println(io, "")

    # println(io, lvl1_indent, "Close orders:       $(acc.close_orders_count)")
    # i = 0
    # for (sec, orders) in acc.close_orders
    #     for o in orders
    #         println(io, lvl2_indent, o)
    #         i += 1
    #         if i == max_print_items
    #             break
    #         end
    #     end
    # end
    # if i < acc.close_orders_count
    #     println(io, lvl2_indent, "[...] $(acc.close_orders_count - i) more items")
    # end
    # println(io, "")

    println(io, lvl1_indent, "Open positions:     $(length(acc.open_positions))")
    i = 0
    total = length(acc.open_positions)
    for pos in acc.open_positions
        i += 1
        println(io, lvl2_indent, pos)
        if i == max_print_items
            break
        end
    end
    if i < total
        println(io, lvl2_indent, "[...] $(total - i) more items")
    end
    println(io, "")

    println(io, lvl1_indent, "Closed positions:   $(length(acc.closed_positions))")
    i = 0
    total = length(acc.closed_positions)
    for pos in acc.closed_positions
        i += 1
        println(io, lvl2_indent, pos)
        if i == max_print_items
            break
        end
    end
    if i < total
        println(io, lvl2_indent, "[...] $(total - i) more items")
    end
    println(io, "")

    println(io, lvl1_indent, "Balance:            $(@sprintf("%.2f", acc.balance))\n")
    println(io, lvl1_indent, "Equity:             $(@sprintf("%.2f", acc.equity))")
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
