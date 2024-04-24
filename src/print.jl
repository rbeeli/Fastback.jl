using PrettyTables
using Printf

# --------------- Instrument ---------------

function Base.show(io::IO, inst::Instrument)
    print(io, "[Instrument] " *
              "index=$(inst.index) " *
              "symbol=$(inst.symbol)")
end

# --------------- Order ---------------

function Base.show(io::IO, o::Order{O,I}) where {O,I}
    print(io, "[Order] $(o.inst.symbol) " *
              "dt=$(o.acc.date_formatter(o.dt))" *
              "px=$(o.inst.price_formatter(o.price)) " *
              "qty=$(o.inst.quantity_formatter(o.quantity)) ")
end

Base.show(order::Order{O,I}) where {O,I} = Base.show(stdout, order)

# --------------- Execution ---------------

function Base.show(io::IO, e::Execution)
    print(io, "[Execution] " *
              "dt=$(e.order.acc.date_formatter(e.dt)) " *
              "fill_px=$(e.order.inst.price_formatter(e.fill_price)) " *
              "fill_qty=$(e.order.inst.quantity_formatter(e.fill_quantity)) " *
              "remain_qty=$(e.order.inst.quantity_formatter(e.remaining_quantity)) " *
              "real_pnl=$(e.order.acc.ccy_formatter(e.realized_pnl)) " *
              "real_qty=$(e.order.inst.quantity_formatter(e.realized_quantity))" *
              "fees_ccy=$(e.order.acc.ccy_formatter(e.fees_ccy))" *
              "pos_avg_px=$(e.order.inst.price_formatter(e.pos_avg_price)) " *
              "pos_qty=$(e.order.inst.quantity_formatter(e.pos_quantity)) ")
end

Base.show(obj::Execution) = Base.show(stdout, obj)

function print_executions(
    io::IO,
    executions::Vector{Execution{O,I}}
    ;
    max_print=25
) where {O,I}
    if length(executions) == 0
        print(io, "\n  No executions\n")
        return
    end

    n_total = length(executions)
    n_shown = min(n_total, max_print)
    n_hidden = n_total - n_shown

    cols = [
        Dict(:name => "Seq", :val => t -> t.seq, :fmt => (e, v) -> v),
        Dict(:name => "Symbol", :val => t -> t.order.inst.symbol, :fmt => (e, v) -> v),
        Dict(:name => "Date", :val => t -> "$(t.order.acc.date_formatter(t.order.dt)) +$(Dates.value(round(t.dt - t.order.dt, Millisecond))) ms", :fmt => (e, v) -> v),
        # Dict(:name => "Qty", :val => t -> t.order.quantity, :fmt => (e, v) -> e.order.inst.quantity_formatter(v)),
        Dict(:name => "Fill qty", :val => t -> t.fill_quantity, :fmt => (e, v) -> e.order.inst.quantity_formatter(v)),
        Dict(:name => "Remain. qty", :val => t -> t.remaining_quantity, :fmt => (e, v) -> e.order.inst.quantity_formatter(v)),
        Dict(:name => "Fill price", :val => t -> t.fill_price, :fmt => (e, v) -> isnan(v) ? "—" : e.order.inst.price_formatter(v)),
        Dict(:name => "Realized P&L", :val => t -> t.realized_pnl, :fmt => (e, v) -> isnan(v) ? "—" : e.order.acc.ccy_formatter(v)),
        Dict(:name => "Fees", :val => t -> t.fees_ccy, :fmt => (e, v) -> e.order.acc.ccy_formatter(v))
    ]
    columns = [c[:name] for c in cols]

    data_columns = []
    for col in cols
        push!(data_columns, map(col[:val], first(executions, n_shown)))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](executions[row_ix], v)

    h_pnl_pos = Highlighter((data, i, j) -> cols[j][:name] == "Realized P&L" && data_columns[j][i] > 0, foreground=0x11BF11)
    h_pnl_neg = Highlighter((data, i, j) -> cols[j][:name] == "Realized P&L" && data_columns[j][i] < 0, foreground=0xDD0000)
    h_qty_pos = Highlighter((data, i, j) -> cols[j][:name] == "Fill qty" && data_columns[j][i] > 0, foreground=0xDD00DD)
    h_qty_neg = Highlighter((data, i, j) -> cols[j][:name] == "Fill qty" && data_columns[j][i] < 0, foreground=0xDDDD00)

    if n_hidden > 0
        pretty_table(
            io,
            data_matrix
            ;
            header=columns,
            highlighters=(h_pnl_pos, h_pnl_neg, h_qty_pos, h_qty_neg),
            formatters=formatter,
            compact_printing=true)
        println(io, " [...] $n_hidden more executions")
    else
        pretty_table(
            io,
            data_matrix
            ;
            header=columns,
            highlighters=(h_pnl_pos, h_pnl_neg, h_qty_pos, h_qty_neg),
            formatters=formatter,
            compact_printing=true)
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
    positions::Vector{Position{O,I}}
    ;
    max_print=50
) where {O,I}
    positions = filter(p -> p.quantity != 0, positions)

    if length(positions) == 0
        return
    end

    n_total = length(positions)
    n_shown = min(n_total, max_print)
    n_hidden = n_total - n_shown

    cols = [
        Dict(:name => "Symbol", :val => t -> t.inst.symbol, :fmt => (p, v) -> v),
        Dict(:name => "Qty", :val => t -> t.quantity, :fmt => (p, v) -> p.inst.quantity_formatter(v)),
        Dict(:name => "Avg. price", :val => t -> t.avg_price, :fmt => (p, v) -> isnan(v) ? "—" : p.inst.price_formatter(v)),
        Dict(:name => "P&L", :val => t -> t.pnl, :fmt => (p, v) -> isnan(v) ? "—" : p.acc.ccy_formatter(v))
    ]
    columns = [c[:name] for c in cols]

    data_columns = []
    for col in cols
        push!(data_columns, map(col[:val], first(positions, n_shown)))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](positions[row_ix], v)

    h_pnl_pos = Highlighter((data, i, j) -> cols[j][:name] == "P&L" && data_columns[j][i] > 0, foreground=0x11BF11)
    h_pnl_neg = Highlighter((data, i, j) -> cols[j][:name] == "P&L" && data_columns[j][i] < 0, foreground=0xDD0000)
    h_qty_pos = Highlighter((data, i, j) -> cols[j][:name] == "Qty" && data_columns[j][i] > 0, foreground=0xDD00DD)
    h_qty_neg = Highlighter((data, i, j) -> cols[j][:name] == "Qty" && data_columns[j][i] < 0, foreground=0xDDDD00)

    if n_hidden > 0
        pretty_table(
            io,
            data_matrix
            ;
            header=columns,
            highlighters=(h_pnl_pos, h_pnl_neg, h_qty_pos, h_qty_neg),
            formatters=formatter,
            compact_printing=true)
        println(io, " [...] $n_hidden more positions")
    else
        pretty_table(
            io,
            data_matrix
            ;
            header=columns,
            highlighters=(h_pnl_pos, h_pnl_neg, h_qty_pos, h_qty_neg),
            formatters=formatter,
            compact_printing=true)
    end
end

function Base.show(io::IO, pos::Position)
    print(io, "[Position] $(pos.inst.symbol) " *
              "px=$(pos.inst.price_formatter(pos.avg_price)) " *
              "qty=$(pos.inst.quantity_formatter(pos.quantity)) " *
              "pnl=$(pos.acc.ccy_formatter(pos.pnl)) " *
              "fees=$(pos.acc.ccy_formatter(pos.fees_ccy))" *
              "($(length(pos.executions)) executions)")
end

Base.show(pos::Position) = Base.show(stdout, pos)

# --------------- Account ---------------

function Base.show(
    io::IO,
    acc::Account{O,I}
    ;
    max_orders=50,
    kwargs...
) where {O,I}
    # volume_digits and price_digits are passed to print_positions(...) via kwargs
    display_width = displaysize(io)[2]

    function get_color(val)
        val >= 0 && return val == 0 ? crayon"#888888" : crayon"#11BF11"
        crayon"#DD0000"
    end

    n_open_pos = count(p -> p.quantity ≉ 0, acc.positions)
    acc_return = total_return(acc)

    title = " ACCOUNT SUMMARY "
    title_line = '━'^(floor(Int64, (display_width - length(title)) / 2))
    println(io, "")
    println(io, title_line * title * title_line)
    print(io, "Balance:         $(acc.ccy_formatter(acc.balance)) (initial $(acc.ccy_formatter(acc.initial_balance)))\n")
    # print(io, " (")
    # print(io, get_color(balance_ret(acc)), "$(@sprintf("%+.2f", balance_ret(acc)*100))%", Crayon(reset=true))
    # print(io, ")\n")
    print(io, "Equity:          $(acc.ccy_formatter(acc.equity))")
    print(io, " (")
    print(io, get_color(acc_return), "$(@sprintf("%+.1f", 100*acc_return))%", Crayon(reset=true))
    print(io, ")\n")
    println(io, "Open positions:  $n_open_pos")
    print_positions(io, acc.positions; kwargs...)
    println(io, "Executions:      $(length(acc.executions))")
    print_executions(io, acc.executions; max_print=max_orders, kwargs...)
    println(io, '━'^display_width)
    print(io, "")
end

Base.show(acc::Account; kwargs...) = Base.show(stdout, acc; kwargs...)
