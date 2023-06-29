using PrettyTables
using Printf
using DataFrames

# --------------- Instrument ---------------

Base.show(io::IO, inst::Instrument) = print(io, "[Instrument] symbol=$(inst.symbol)  index=$(inst.index)")

# --------------- BidAsk ---------------

Base.show(io::IO, ba::BidAsk) = print(io, "[BidAsk] dt=$(ba.dt)  bid=$(ba.bid)  ask=$(ba.ask)")

# --------------- Order ---------------

function print_orders(
    io::IO,
    orders::Vector{Order{O}};
    max_print=25,
    volume_digits=1,
    price_digits=2
) where {O}
    if length(orders) == 0
        print(io, "\n  No orders\n")
        return
    end

    date_fmt = dateformat"yyyy-mm-dd HH:MM:SS"
    vol_fmt = x -> string(round(x, digits=volume_digits))
    price_fmt = x -> string(round(x, digits=price_digits))

    # ; "Flag 1"; "Flag 2"; "Flag 3"
    columns = ["Symbol"; "Quantity"; "Date"; "Execution date"; "Execution price"; "Execution quantity"; "Realized P&L"]

    ix_date = findfirst(columns .== "Date")
    ix_exe_date = findfirst(columns .== "Execution date")
    ix_quantity = findfirst(columns .== "Quantity")
    ix_exe_quantity = findfirst(columns .== "Execution quantity")
    ix_avg_price = findfirst(columns .== "Avg price")
    ix_exe_price = findfirst(columns .== "Execution price")
    ix_pnl = findfirst(columns .== "Realized P&L")
    # ix_flag1 = findfirst(columns .== "Flag 1")
    # ix_flag2 = findfirst(columns .== "Flag 2")
    # ix_flag3 = findfirst(columns .== "Flag 3")

    formatter = (v, i, j) -> begin
        o = v
        if j ∈ [ix_date, ix_exe_date]
            o = Dates.format(v, date_fmt)
        elseif j ∈ [ix_quantity, ix_exe_quantity]
            o = vol_fmt(v)
        elseif j ∈ [ix_exe_price, ix_avg_price, ix_pnl]
            o = isnan(v) ? "—" : price_fmt(v)
        # elseif j ∈ [ix_flag1, ix_flag2, ix_flag3]
        #     o = string(v)
        end
        o
    end

    n_total = length(orders)
    n_shown = min(n_total, max_print)
    n_hidden = n_total - n_shown

    #  o.flag1 o.flag2 o.flag3
    data = map(o -> [o.inst.symbol o.quantity o.dt o.execution.dt o.execution.price o.execution.quantity o.execution.realized_pnl], first(orders, n_shown))
    data = reduce(vcat, data)

    h_pos_green = Highlighter((data, i, j) -> j == ix_pnl && data[i, j] > 0, bold=true, foreground=:green)
    h_neg_red = Highlighter((data, i, j) -> j == ix_pnl && data[i, j] < 0, bold=true, foreground=:red)

    if n_hidden > 0
        df = DataFrame(data, columns)
        pretty_table(io, df;
            highlighters = (h_pos_green, h_neg_red),
            formatters = formatter,
            compact_printing = false)
        println(io, " [...] $n_hidden more orders")
    else
        df = DataFrame(data, columns)
        pretty_table(io, df;
            highlighters = (h_pos_green, h_neg_red),
            formatters = formatter,
            compact_printing = false)
    end
end

function Base.show(io::IO, o::Order{O}) where {O}
    print(io, "[Order] $(o.inst.symbol)  qty=$(@sprintf("%+.2f", o.quantity))  dt=$(Dates.format(o.dt, "yyyy-mm-dd HH:MM:SS"))  execution=$(o.execution)")
end

#   flags=[$(o.flag1),$(o.flag2),$(o.flag3)]

Base.show(order::Order{O}) where {O} = Base.show(stdout, order)

# --------------- OrderExecution ---------------

function Base.show(io::IO, oe::OrderExecution)
    print(io, "[OrderExe] qty=$(@sprintf("%+.2f", oe.quantity))  pos_avg_price=$(oe.pos_avg_price)  "*
        "pos_quantity=$(oe.pos_quantity)  price=$(oe.price)  dt=$(Dates.format(oe.dt, "yyyy-mm-dd HH:MM:SS"))  "*
        "realized_pnl=$(oe.realized_pnl)  realized_quantity=$(oe.realized_quantity)")
end

Base.show(order_exe::OrderExecution) = Base.show(stdout, order_exe)

# --------------- Position ---------------

function print_positions(
    positions::Vector{Position{O}};
    max_print=50,
    volume_digits=1,
    price_digits=2,
    kwargs...
) where {O}
    print_positions(
        stdout,
        positions;
        max_print,
        volume_digits,
        price_digits,
        kwargs...)
end

function print_positions(
    io::IO,
    positions::Vector{Position{O}};
    max_print=50,
    volume_digits=1,
    price_digits=2
) where {O}
    positions = filter(p -> p.quantity != 0, positions)

    if length(positions) == 0
        print(io, "\n  No open positions\n")
        return
    end

    vol_fmt = x -> string(round(x, digits=volume_digits))
    price_fmt = x -> string(round(x, digits=price_digits))

    columns = ["Symbol"; "Quantity"; "Avg price"; "P&L"; "Orders count"]

    ix_quantity = findfirst(columns .== "Quantity")
    ix_avg_price = findfirst(columns .== "Avg price")
    ix_pnl = findfirst(columns .== "P&L")

    formatter = (v, i, j) -> begin
        o = v
        if j == ix_quantity
            o = vol_fmt(v)
        elseif j == ix_avg_price || j == ix_pnl
            o = isnan(v) ? "—" : price_fmt(v)
        end
        o
    end

    n_total = length(positions)
    n_shown = min(n_total, max_print)
    n_hidden = n_total - n_shown

    data = map(p -> [p.inst.symbol p.quantity p.avg_price p.pnl length(p.orders_history)], first(positions, n_shown))
    data = reduce(vcat, data)

    h_pos_green = Highlighter((data, i, j) -> j == ix_pnl && data[i, j] > 0, bold=true, foreground=:green)
    h_neg_red = Highlighter((data, i, j) -> j == ix_pnl && data[i, j] < 0, bold=true, foreground=:red)

    if n_hidden > 0
        df = DataFrame(data, columns)
        pretty_table(io, df;
            highlighters = (h_pos_green, h_neg_red),
            formatters = formatter,
            compact_printing = false)
        println(io, " [...] $n_hidden more positions")
    else
        df = DataFrame(data, columns)
        pretty_table(io, df;
            highlighters = (h_pos_green, h_neg_red),
            formatters = formatter,
            compact_printing = false)
    end
end

function Base.show(io::IO, pos::Position{O}) where {O}
    quantity_str = @sprintf("%+.2f", pos.quantity)
    pnl_str = @sprintf("%+.2f", pos.pnl)
    print(io, "[Position] $(pos.inst.symbol) $quantity_str @ $(pos.avg_price)  pnl=$pnl_str  " *
              "($(length(pos.orders_history)) orders)")
end

Base.show(pos::Position) = Base.show(stdout, pos)

# --------------- Account ---------------

function Base.show(io::IO, acc::Account{O}; max_orders=50, volume_digits=1, price_digits=2, kwargs...) where {O}
    # volume_digits and price_digits are passed to print_positions(...) via kwargs
    display_width = displaysize()[2]

    function get_color(val)
        if val >= 0
            return val == 0 ? crayon"rgb(128,128,128)" : crayon"green"
        end
        return crayon"red"
    end

    n_open_positions = count(p -> p.quantity != 0, acc.positions)

    title = " ACCOUNT SUMMARY "
    title_line = '━'^(floor(Int64, (display_width - length(title)) / 2))
    println(io, "")
    println(io, title_line * title * title_line)
    println(io, " ", "Initial balance:    $(@sprintf("%.2f", acc.initial_balance))")
    print(io, " ", "Balance:            $(@sprintf("%.2f", acc.balance))\n")
    # print(io, " (")
    # print(io, get_color(balance_ret(acc)), "$(@sprintf("%+.2f", balance_ret(acc)*100))%", Crayon(reset=true))
    # print(io, ")\n")
    print(io, " ", "Equity:             $(@sprintf("%.2f", acc.equity))")
    print(io, " (")
    print(io, get_color(equity_return(acc)), "$(@sprintf("%+.2f", equity_return(acc)*100))%", Crayon(reset=true))
    print(io, ")\n")
    println(io, "")
    println(io, " ", "Positions:          $n_open_positions")
    print_positions(io, acc.positions; kwargs...)
    println(io, "")
    println(io, " ", "Orders history:             $(length(acc.orders_history))")
    print_orders(io, acc.orders_history; max_print=max_orders, kwargs...)
    println(io, "")
    println(io, '━'^display_width)
    println(io, "")
end

Base.show(acc::Account{O}; kwargs...) where {O} = Base.show(stdout, acc; kwargs...)
