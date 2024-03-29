using PrettyTables
using Printf
using DataFrames

# --------------- Instrument ---------------

Base.show(io::IO, inst::Instrument) = print(io, "[Instrument] symbol=$(inst.symbol)  index=$(inst.index)")

# --------------- BidAsk ---------------

Base.show(io::IO, ba::BidAsk) = print(io, "[BidAsk] dt=$(ba.dt)  bid=$(ba.bid)  ask=$(ba.ask)")

# --------------- Order ---------------

function Base.show(io::IO, o::Order{O,I}) where {O,I}
    print(io, "[Order] $(o.inst.symbol)  qty=$(@sprintf("%+.2f", o.quantity))  dt=$(Dates.format(o.dt, "yyyy-mm-dd HH:MM:SS"))")
end

Base.show(order::Order{O,I}) where {O,I} = Base.show(stdout, order)

# --------------- Execution ---------------

function Base.show(io::IO, oe::Execution)
    print(io, "[Execution] qty=$(@sprintf("%+.2f", oe.quantity))  pos_avg_price=$(oe.pos_avg_price)  "*
        "pos_quantity=$(oe.pos_quantity)  price=$(oe.price)  dt=$(Dates.format(oe.dt, "yyyy-mm-dd HH:MM:SS"))  "*
        "realized_pnl=$(oe.realized_pnl)  realized_quantity=$(oe.realized_quantity)")
end

Base.show(order_exe::Execution) = Base.show(stdout, order_exe)

# --------------- Transaction ---------------

function print_transactions(
    io::IO,
    txs::Vector{Transaction{O,I}};
    max_print=25,
    volume_digits=1,
    price_digits=2
) where {O,I}
    if length(txs) == 0
        print(io, "\n  No transactions\n")
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

    formatter = (v, i, j) -> begin
        o = v
        if j ∈ [ix_date, ix_exe_date]
            o = Dates.format(v, date_fmt)
        elseif j ∈ [ix_quantity, ix_exe_quantity]
            o = vol_fmt(v)
        elseif j ∈ [ix_exe_price, ix_avg_price, ix_pnl]
            o = isnan(v) ? "—" : price_fmt(v)
        end
        o
    end

    n_total = length(txs)
    n_shown = min(n_total, max_print)
    n_hidden = n_total - n_shown

    data = map(t -> [t.order.inst.symbol t.order.quantity t.order.dt t.execution.dt t.execution.price t.execution.quantity t.execution.realized_pnl], first(txs, n_shown))
    data = reduce(vcat, data)

    h_pos_green = Highlighter((data, i, j) -> j == ix_pnl && data[i, j] > 0, bold=true, foreground=:green)
    h_neg_red = Highlighter((data, i, j) -> j == ix_pnl && data[i, j] < 0, bold=true, foreground=:red)

    if n_hidden > 0
        df = DataFrame(data, columns)
        pretty_table(io, df;
            highlighters = (h_pos_green, h_neg_red),
            formatters = formatter,
            compact_printing = false)
        println(io, " [...] $n_hidden more transactions")
    else
        df = DataFrame(data, columns)
        pretty_table(io, df;
            highlighters = (h_pos_green, h_neg_red),
            formatters = formatter,
            compact_printing = false)
    end
end

# --------------- Position ---------------

function print_positions(
    positions::Vector{Position{O,I}};
    max_print=50,
    volume_digits=1,
    price_digits=2,
    kwargs...
) where {O,I}
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
    positions::Vector{Position{O,I}};
    max_print=50,
    volume_digits=1,
    price_digits=2
) where {O,I}
    positions = filter(p -> p.quantity != 0, positions)

    if length(positions) == 0
        print(io, "\n  No open positions\n")
        return
    end

    vol_fmt = x -> string(round(x, digits=volume_digits))
    price_fmt = x -> string(round(x, digits=price_digits))

    columns = ["Symbol"; "Quantity"; "Avg price"; "P&L"; "Tx count"]

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

    data = map(p -> [p.inst.symbol p.quantity p.avg_price p.pnl length(p.transactions)], first(positions, n_shown))
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

function Base.show(io::IO, pos::Position{O,I}) where {O,I}
    quantity_str = @sprintf("%+.2f", pos.quantity)
    pnl_str = @sprintf("%+.2f", pos.pnl)
    print(io, "[Position] $(pos.inst.symbol) $quantity_str @ $(pos.avg_price)  pnl=$pnl_str  " *
              "($(length(pos.transactions)) transactions)")
end

Base.show(pos::Position{O,I}) where {O,I} = Base.show(stdout, pos)

# --------------- Account ---------------

function Base.show(io::IO, acc::Account{O,I}; max_orders=50, volume_digits=1, price_digits=2, kwargs...) where {O,I}
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
    println(io, " ", "Transactions:       $(length(acc.transactions))")
    print_transactions(io, acc.transactions; max_print=max_orders, kwargs...)
    println(io, "")
    println(io, '━'^display_width)
    println(io, "")
end

Base.show(acc::Account{O,I}; kwargs...) where {O,I} = Base.show(stdout, acc; kwargs...)
