using PrettyTables
using Printf
using Dates

# --------------- Trades ---------------

function print_trades(
    io::IO,
    acc::Account{OData,IData,AData,ER}
    ;
    max_print=25
) where {OData,IData,AData,ER}
    trades = acc.trades

    length(trades) == 0 && return

    n_total = length(trades)
    n_shown = min(n_total, max_print)
    n_hidden = n_total - n_shown

    cols = [
        Dict(:name => "ID", :val => t -> t.tid, :fmt => (t, v) -> v),
        Dict(:name => "Symbol", :val => t -> t.order.inst.symbol, :fmt => (t, v) -> v),
        # Dict(:name => "Date", :val => t -> "$(format_date(acc, t.order.date)) +$(Dates.value(round(t.date - t.order.date, Millisecond))) ms", :fmt => (e, v) -> v),
        Dict(:name => "Date", :val => t -> "$(format_date(acc, t.date))", :fmt => (e, v) -> v),
        # Dict(:name => "Qty", :val => t -> t.order.quantity, :fmt => (e, v) -> format_quantity(instrument(e), v)),
        Dict(:name => "Fill qty", :val => t -> t.fill_quantity, :fmt => (t, v) -> format_base(t.order.inst, v)),
        Dict(:name => "Remain. qty", :val => t -> t.remaining_quantity, :fmt => (t, v) -> format_base(t.order.inst, v)),
        Dict(:name => "Fill price", :val => t -> t.fill_price, :fmt => (t, v) -> isnan(v) ? "—" : format_quote(t.order.inst, v)),
        Dict(:name => "Realized P&L", :val => t -> t.realized_pnl, :fmt => (t, v) -> isnan(v) ? "—" : format_quote(t.order.inst, v)),
        Dict(:name => "Fee", :val => t -> t.fee_ccy, :fmt => (t, v) -> format_quote(t.order.inst, v))
    ]
    columns = [c[:name] for c in cols]

    data_columns = []
    for col in cols
        push!(data_columns, map(col[:val], first(trades, n_shown)))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](trades[row_ix], v)

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
        println(io, " [...] $n_hidden more trades")
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

# --------------- Positions ---------------

function print_positions(
    acc::Account{OData,IData,AData,ER}
    ;
    max_print=50,
    kwargs...
) where {OData,IData,AData,ER}
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
    acc::Account{OData,IData,AData,ER}
    ;
    max_print=50
) where {OData,IData,AData,ER}
    positions = filter(p -> p.quantity != 0, acc.positions)

    length(positions) == 0 && return

    n_total = length(positions)
    n_shown = min(n_total, max_print)
    n_hidden = n_total - n_shown

    cols = [
        Dict(:name => "Symbol", :val => t -> t.inst.symbol, :fmt => (p, v) -> v),
        Dict(:name => "Qty", :val => t -> t.quantity, :fmt => (p, v) -> format_base(p.inst, v)),
        Dict(:name => "Avg. price", :val => t -> t.avg_price, :fmt => (p, v) -> isnan(v) ? "—" : format_quote(p.inst, v)),
        Dict(:name => "P&L", :val => t -> t.pnl, :fmt => (p, v) -> isnan(v) ? "—" : format_quote(p.inst, v))
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

# ---------------- Assets ----------------

function print_assets(
    io::IO,
    acc::Account{OData,IData,AData,ER}
) where {OData,IData,AData,ER}
    assets = acc.assets

    length(assets) == 0 && return

    cols = [
        Dict(
            :name => "",
            :val => a -> a.symbol,
            :fmt => (a, v) -> v
        ),
        Dict(
            :name => "Value",
            :val => a -> get_asset_value(acc, a),
            :fmt => (a, v) -> format_value(a, v)
        ),
        Dict(
            :name => "Value $(acc.base_asset.symbol)",
            :val => a -> get_asset_value_base(acc, a),
            :fmt => (a, v) -> format_value(a, v)
        )
    ]
    columns = [c[:name] for c in cols]

    data_columns = []
    for col in cols
        push!(data_columns, map(col[:val], assets))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](assets[row_ix], v)

    h_val_pos = Highlighter((data, i, j) -> startswith(cols[j][:name], "Value") && data_columns[j][i] > 0, foreground=0x11BF11)
    h_val_neg = Highlighter((data, i, j) -> startswith(cols[j][:name], "Value") && data_columns[j][i] < 0, foreground=0xDD0000)

    pretty_table(
        io,
        data_matrix
        ;
        header=columns,
        highlighters=(h_val_pos, h_val_neg),
        formatters=formatter,
        compact_printing=true)
end

# --------------- Account ---------------

function Base.show(
    io::IO,
    acc::Account{OData,IData,AData,ER}
    ;
    max_trades=50,
    kwargs...
) where {OData,IData,AData,ER}
    display_width = displaysize(io)[2]

    function get_color(val)
        val >= 0 && return val == 0 ? crayon"#888888" : crayon"#11BF11"
        crayon"#DD0000"
    end

    title = " ACCOUNT SUMMARY "
    title_line = '━'^(floor(Int64, (display_width - length(title)) / 2))
    println(io, title_line * title * title_line)
    print(io, "Total balance:     $(format_base(acc, total_balance(acc))) $(acc.base_asset.symbol)\n")
    print(io, "Total equity:      $(format_base(acc, total_equity(acc))) $(acc.base_asset.symbol)\n")
    print(io, "\n")
    print(io, "\033[1mAsset balances\033[0m ($(length(acc.assets)))\n")
    print_assets(io, acc; kwargs...)
    # print(io, get_color(acc_return), "$(@sprintf("%+.1f", 100*acc_return))%", Crayon(reset=true))
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
