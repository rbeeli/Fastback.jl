using PrettyTables
using Crayons
using Dates
import Printf

# --------------- Trades ---------------

function print_trades(
    io::IO,
    acc::Account{OData,IData,CData}
    ;
    max_print=25
) where {OData,IData,CData}
    trades = acc.trades

    length(trades) == 0 && return

    n_total = length(trades)
    n_shown = min(n_total, max_print)
    n_hidden = n_total - n_shown

    cols = [
        Dict(:name => "ID", :val => t -> t.tid, :fmt => (t, v) -> v),
        Dict(:name => "Symbol", :val => t -> t.order.inst.symbol, :fmt => (t, v) -> v),
        # Dict(:name => "Date", :val => t -> "$(format_datetime(acc, t.order.date)) +$(Dates.value(round(t.date - t.order.date, Millisecond))) ms", :fmt => (e, v) -> v),
        Dict(:name => "Date", :val => t -> "$(format_datetime(acc, t.date))", :fmt => (e, v) -> v),
        Dict(:name => "Qty", :val => t -> t.order.quantity, :fmt => (t, v) -> format_base(t.order.inst, v)),
        Dict(:name => "Filled", :val => t -> t.fill_qty, :fmt => (t, v) -> format_base(t.order.inst, v)),
        # Dict(:name => "Remain. qty", :val => t -> t.remaining_qty, :fmt => (t, v) -> format_base(t.order.inst, v)),
        Dict(:name => "Price", :val => t -> t.fill_price, :fmt => (t, v) -> isnan(v) ? "—" : format_quote(t.order.inst, v)),
        Dict(:name => "TP", :val => t -> t.order.take_profit, :fmt => (t, v) -> isnan(v) ? "—" : format_quote(t.order.inst, v)),
        Dict(:name => "SL", :val => t -> t.order.stop_loss, :fmt => (t, v) -> isnan(v) ? "—" : format_quote(t.order.inst, v)),
        Dict(:name => "Ccy", :val => t -> t.order.inst.quote_symbol, :fmt => (t, v) -> v),
        Dict(:name => "P&L", :val => t -> t.realized_pnl, :fmt => (t, v) -> isnan(v) ? "—" : format_quote(t.order.inst, v)),
        Dict(:name => "Return", :val => t -> realized_return(t), :fmt => (t, v) -> @sprintf("%.2f%%", 100v)),
        Dict(:name => "Comm.", :val => t -> t.commission, :fmt => (t, v) -> format_quote(t.order.inst, v)),
    ]

    # add "Metadata" column if OData is not Nothing
    if OData !== Nothing
        push!(cols, Dict(:name => "Metadata", :val => t -> t.order.metadata, :fmt => (t, v) -> v))
    end

    columns = [c[:name] for c in cols]

    data_columns = []
    for col in cols
        push!(data_columns, map(col[:val], first(trades, n_shown)))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](trades[row_ix], v)

    h_pnl_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "P&L" && data_columns[j][i] > 0, crayon"#11BF11")
    h_pnl_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "P&L" && data_columns[j][i] < 0, crayon"#DD0000")
    h_qty_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "Filled" && data_columns[j][i] > 0, crayon"#DD00DD")
    h_qty_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "Filled" && data_columns[j][i] < 0, crayon"#DDDD00")
    h_ret_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "Return" && data_columns[j][i] > 0, crayon"#11BF11")
    h_ret_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "Return" && data_columns[j][i] < 0, crayon"#DD0000")

    if n_hidden > 0
        pretty_table(
            io,
            data_matrix
            ;
            column_labels=columns,
            highlighters=[h_pnl_pos, h_pnl_neg, h_qty_pos, h_qty_neg, h_ret_pos, h_ret_neg],
            formatters=[formatter],
            compact_printing=true)
        println(io, " [...] $n_hidden more trades")
    else
        pretty_table(
            io,
            data_matrix
            ;
            column_labels=columns,
            highlighters=[h_pnl_pos, h_pnl_neg, h_qty_pos, h_qty_neg, h_ret_pos, h_ret_neg],
            formatters=[formatter],
            compact_printing=true)
    end
end

# --------------- Positions ---------------

function print_positions(
    acc::Account{OData,IData,CData}
    ;
    max_print=50,
    kwargs...
) where {OData,IData,CData}
    print_positions(
        stdout,
        acc
        ;
        max_print,
        kwargs...
    )
end

function print_positions(
    io::IO,
    acc::Account{OData,IData,CData}
    ;
    max_print=50
) where {OData,IData,CData}
    positions = filter(p -> p.quantity != 0, acc.positions)

    length(positions) == 0 && return

    n_total = length(positions)
    n_shown = min(n_total, max_print)
    n_hidden = n_total - n_shown

    cols = [
        Dict(:name => "Symbol", :val => t -> t.inst.symbol, :fmt => (p, v) -> v),
        Dict(:name => "Qty", :val => t -> t.quantity, :fmt => (p, v) -> format_base(p.inst, v)),
        Dict(:name => "Avg. price", :val => t -> t.avg_price, :fmt => (p, v) -> isnan(v) ? "—" : format_quote(p.inst, v)),
        Dict(:name => "Ccy", :val => t -> t.inst.quote_symbol, :fmt => (p, v) -> v),
        Dict(:name => "P&L", :val => t -> t.pnl_local, :fmt => (p, v) -> isnan(v) ? "—" : format_quote(p.inst, v)),
    ]
    columns = [c[:name] for c in cols]

    data_columns = []
    for col in cols
        push!(data_columns, map(col[:val], first(positions, n_shown)))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](positions[row_ix], v)

    h_pnl_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "P&L" && data_columns[j][i] > 0, crayon"#11BF11")
    h_pnl_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "P&L" && data_columns[j][i] < 0, crayon"#DD0000")
    h_qty_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "Qty" && data_columns[j][i] > 0, crayon"#DD00DD")
    h_qty_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "Qty" && data_columns[j][i] < 0, crayon"#DDDD00")

    if n_hidden > 0
        pretty_table(
            io,
            data_matrix
            ;
            column_labels=columns,
            highlighters=[h_pnl_pos, h_pnl_neg, h_qty_pos, h_qty_neg],
            formatters=[formatter],
            compact_printing=true)
        println(io, " [...] $n_hidden more positions")
    else
        pretty_table(
            io,
            data_matrix
            ;
            column_labels=columns,
            highlighters=[h_pnl_pos, h_pnl_neg, h_qty_pos, h_qty_neg],
            formatters=[formatter],
            compact_printing=true)
    end
end

# ---------------- Cash balances ----------------

function print_cash_balances(
    io::IO,
    acc::Account{OData,IData,CData}
) where {OData,IData,CData}
    length(acc.balances) == 0 && return

    cols = [
        Dict(
            :name => "",
            :val => a -> a.symbol,
            :fmt => (a, v) -> v
        ),
        Dict(
            :name => "Value",
            :val => a -> cash_balance(acc, a),
            :fmt => (a, v) -> format_cash(a, v)
        ),
    ]
    columns = [c[:name] for c in cols]

    data_columns = []
    for col in cols
        push!(data_columns, map(col[:val], acc.cash))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](acc.cash[row_ix], v)

    h_val_pos = TextHighlighter((data, i, j) -> startswith(cols[j][:name], "Value") && data_columns[j][i] > 0, crayon"#11BF11")
    h_val_neg = TextHighlighter((data, i, j) -> startswith(cols[j][:name], "Value") && data_columns[j][i] < 0, crayon"#DD0000")

    pretty_table(
        io,
        data_matrix
        ;
        column_labels=columns,
        highlighters=[h_val_pos, h_val_neg],
        formatters=[formatter],
        compact_printing=true)
end

# ---------------- Equity balances ----------------

function print_equity_balances(
    io::IO,
    acc::Account{OData,IData,CData}
) where {OData,IData,CData}
    length(acc.equities) == 0 && return

    cols = [
        Dict(
            :name => "",
            :val => a -> a.symbol,
            :fmt => (a, v) -> v
        ),
        Dict(
            :name => "Value",
            :val => a -> equity(acc, a),
            :fmt => (a, v) -> format_cash(a, v)
        ),
    ]
    columns = [c[:name] for c in cols]

    data_columns = []
    for col in cols
        push!(data_columns, map(col[:val], acc.cash))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](acc.cash[row_ix], v)

    h_val_pos = TextHighlighter((data, i, j) -> startswith(cols[j][:name], "Value") && data_columns[j][i] > 0, crayon"#11BF11")
    h_val_neg = TextHighlighter((data, i, j) -> startswith(cols[j][:name], "Value") && data_columns[j][i] < 0, crayon"#DD0000")

    pretty_table(
        io,
        data_matrix
        ;
        column_labels=columns,
        highlighters=[h_val_pos, h_val_neg],
        formatters=[formatter],
        compact_printing=true)
end

# --------------- Account ---------------

function Base.show(
    io::IO,
    acc::Account{OData,IData,CData}
    ;
    max_trades=50,
    kwargs...
) where {OData,IData,CData}
    display_width = displaysize(io)[2]

    function get_color(val)
        val >= 0 && return val == 0 ? crayon"#888888" : crayon"#11BF11"
        crayon"#DD0000"
    end

    title = " ACCOUNT SUMMARY "
    title_line = '━'^(floor(Int64, (display_width - length(title)) / 2))
    println(io, title_line * title * title_line)
    print(io, "\033[1mCash balances\033[0m ($(length(acc.balances)))\n")
    print_cash_balances(io, acc; kwargs...)
    print(io, "\n")
    print(io, "\033[1mEquity balances\033[0m ($(length(acc.equities)))\n")
    print_equity_balances(io, acc; kwargs...)
    print(io, "\n")
    print(io, "\033[1mPositions\033[0m ($(count(has_exposure.(acc.positions))))\n")
    print_positions(io, acc; kwargs...)
    print(io, "\n")
    print(io, "\033[1mTrades\033[0m ($(length(acc.trades)))\n")
    print_trades(io, acc; max_print=max_trades, kwargs...)
    println(io, '━'^display_width)
    print(io, "")
end

Base.show(acc::Account; kwargs...) = Base.show(stdout, acc; kwargs...)
