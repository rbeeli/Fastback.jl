using PrettyTables
using Crayons
using Dates
import Printf

# --------------- Trades ---------------

"""
Pretty-print trades for an account.
"""
function print_trades(
    io::IO,
    acc::Account{TTime}
    ;
    max_print=25
) where {TTime<:Dates.AbstractTime}
    trades = acc.trades
    length(trades) == 0 && return

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
        Dict(:name => "Ccy", :val => t -> t.order.inst.settle_symbol, :fmt => (t, v) -> v),
        Dict(:name => "Fill P&L", :val => t -> t.fill_pnl_settle, :fmt => (t, v) -> begin
            cash = acc.ledger.cash[t.order.inst.settle_cash_index]
            isnan(v) ? "—" : format_cash(cash, v)
        end),
        Dict(:name => "Cash Δ", :val => t -> t.cash_delta_settle, :fmt => (t, v) -> begin
            cash = acc.ledger.cash[t.order.inst.settle_cash_index]
            format_cash(cash, v)
        end),
        Dict(:name => "Return (gross)", :val => t -> realized_return_gross(t), :fmt => (t, v) -> isnan(v) ? "—" : @sprintf("%.2f%%", 100v)),
        Dict(:name => "Return (net)", :val => t -> realized_return_net(t), :fmt => (t, v) -> isnan(v) ? "—" : @sprintf("%.2f%%", 100v)),
        Dict(:name => "Comm.", :val => t -> t.commission_settle, :fmt => (t, v) -> begin
            cash = acc.ledger.cash[t.order.inst.settle_cash_index]
            format_cash(cash, v)
        end),
    ]

    column_labels = [c[:name] for c in cols]
    data_columns = []
    for col in cols
        push!(data_columns, map(col[:val], trades))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](trades[row_ix], v)

    h_pnl_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "Fill P&L" && data_columns[j][i] > 0, crayon"#11BF11")
    h_pnl_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "Fill P&L" && data_columns[j][i] < 0, crayon"#DD0000")
    h_qty_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "Filled" && data_columns[j][i] > 0, crayon"#DD00DD")
    h_qty_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "Filled" && data_columns[j][i] < 0, crayon"#DDDD00")
    h_ret_gross_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "Return (gross)" && data_columns[j][i] > 0, crayon"#11BF11")
    h_ret_gross_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "Return (gross)" && data_columns[j][i] < 0, crayon"#DD0000")
    h_ret_net_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "Return (net)" && data_columns[j][i] > 0, crayon"#11BF11")
    h_ret_net_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "Return (net)" && data_columns[j][i] < 0, crayon"#DD0000")

    pretty_table(
        io,
        data_matrix
        ;
        column_labels=column_labels,
        highlighters=[h_pnl_pos, h_pnl_neg, h_qty_pos, h_qty_neg, h_ret_gross_pos, h_ret_gross_neg, h_ret_net_pos, h_ret_net_neg],
        formatters=[formatter],
        compact_printing=true,
        vertical_crop_mode=:middle,
        maximum_number_of_rows=max_print,
        fit_table_in_display_vertically=false,
    )
end

# --------------- Cashflows ---------------

"""
Pretty-print cashflows for an account.
"""
function print_cashflows(
    acc::Account{TTime}
    ;
    max_print=50
) where {TTime<:Dates.AbstractTime}
    print_cashflows(stdout, acc; max_print)
end

function print_cashflows(
    io::IO,
    acc::Account{TTime}
    ;
    max_print=50
) where {TTime<:Dates.AbstractTime}
    flows = acc.cashflows
    isempty(flows) && return
    cash = acc.ledger.cash
    positions = acc.positions

    cols = [
        Dict(:name => "ID", :val => cf -> cf.id, :fmt => (cf, v) -> v),
        Dict(:name => "Date", :val => cf -> format_datetime(acc, cf.dt), :fmt => (cf, v) -> v),
        Dict(:name => "Kind", :val => cf -> cf.kind, :fmt => (cf, v) -> v),
        Dict(:name => "Cash", :val => cf -> cash[cf.cash_index].symbol, :fmt => (cf, v) -> v),
        Dict(:name => "Amount", :val => cf -> cf.amount, :fmt => (cf, v) -> format_cash(cash[cf.cash_index], v)),
        Dict(:name => "Inst", :val => cf -> cf.inst_index, :fmt => (cf, v) -> v == 0 ? "—" : string(positions[v].inst.symbol)),
    ]

    column_labels = [c[:name] for c in cols]
    data_columns = []
    for col in cols
        push!(data_columns, map(col[:val], flows))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](flows[row_ix], v)

    h_amt_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "Amount" && data_columns[j][i] > 0, crayon"#11BF11")
    h_amt_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "Amount" && data_columns[j][i] < 0, crayon"#DD0000")

    pretty_table(
        io,
        data_matrix
        ;
        column_labels=column_labels,
        highlighters=[h_amt_pos, h_amt_neg],
        formatters=[formatter],
        compact_printing=true,
        vertical_crop_mode=:middle,
        maximum_number_of_rows=max_print,
        fit_table_in_display_vertically=false,
    )
end

# --------------- Positions ---------------

"""
Pretty-print open positions for an account.
"""
function print_positions(
    acc::Account{TTime}
    ;
    max_print=50,
    kwargs...
) where {TTime<:Dates.AbstractTime}
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
    acc::Account{TTime}
    ;
    max_print=50
) where {TTime<:Dates.AbstractTime}
    positions = filter(p -> p.quantity != 0, acc.positions)
    length(positions) == 0 && return

    cols = [
        Dict(:name => "Symbol", :val => t -> t.inst.symbol, :fmt => (p, v) -> v),
        Dict(:name => "Qty", :val => t -> t.quantity, :fmt => (p, v) -> format_base(p.inst, v)),
        Dict(:name => "Entry px", :val => t -> t.avg_entry_price, :fmt => (p, v) -> isnan(v) ? "—" : format_quote(p.inst, v)),
        Dict(:name => "Ccy", :val => t -> t.inst.quote_symbol, :fmt => (p, v) -> v),
        Dict(:name => "P&L", :val => t -> t.pnl_quote, :fmt => (p, v) -> isnan(v) ? "—" : format_quote(p.inst, v)),
    ]

    column_labels = [c[:name] for c in cols]
    data_columns = []
    for col in cols
        push!(data_columns, map(col[:val], positions))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](positions[row_ix], v)

    h_pnl_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "P&L" && data_columns[j][i] > 0, crayon"#11BF11")
    h_pnl_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "P&L" && data_columns[j][i] < 0, crayon"#DD0000")
    h_qty_pos = TextHighlighter((data, i, j) -> cols[j][:name] == "Qty" && data_columns[j][i] > 0, crayon"#DD00DD")
    h_qty_neg = TextHighlighter((data, i, j) -> cols[j][:name] == "Qty" && data_columns[j][i] < 0, crayon"#DDDD00")

    pretty_table(
        io,
        data_matrix
        ;
        column_labels=column_labels,
        highlighters=[h_pnl_pos, h_pnl_neg, h_qty_pos, h_qty_neg],
        formatters=[formatter],
        compact_printing=true,
        vertical_crop_mode=:middle,
        maximum_number_of_rows=max_print,
        fit_table_in_display_vertically=false,
    )
end

# ---------------- Cash balances ----------------

"""
Pretty-print cash balances for an account.
"""
function print_cash_balances(
    io::IO,
    acc::Account{TTime}
) where {TTime<:Dates.AbstractTime}
    length(acc.ledger.balances) == 0 && return

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
        push!(data_columns, map(col[:val], acc.ledger.cash))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](acc.ledger.cash[row_ix], v)

    h_val_pos = TextHighlighter((data, i, j) -> startswith(cols[j][:name], "Value") && data_columns[j][i] > 0, crayon"#11BF11")
    h_val_neg = TextHighlighter((data, i, j) -> startswith(cols[j][:name], "Value") && data_columns[j][i] < 0, crayon"#DD0000")

    pretty_table(
        io,
        data_matrix
        ;
        column_labels=columns,
        highlighters=[h_val_pos, h_val_neg],
        formatters=[formatter],
        compact_printing=true,
        fit_table_in_display_vertically=false,
    )
end

# ---------------- Equity balances ----------------

"""
Pretty-print equity balances for an account.
"""
function print_equity_balances(
    io::IO,
    acc::Account{TTime}
) where {TTime<:Dates.AbstractTime}
    length(acc.ledger.equities) == 0 && return

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
        push!(data_columns, map(col[:val], acc.ledger.cash))
    end
    data_matrix = reduce(hcat, data_columns)

    formatter = (v, row_ix, col_ix) -> cols[col_ix][:fmt](acc.ledger.cash[row_ix], v)

    h_val_pos = TextHighlighter((data, i, j) -> startswith(cols[j][:name], "Value") && data_columns[j][i] > 0, crayon"#11BF11")
    h_val_neg = TextHighlighter((data, i, j) -> startswith(cols[j][:name], "Value") && data_columns[j][i] < 0, crayon"#DD0000")

    pretty_table(
        io,
        data_matrix
        ;
        column_labels=columns,
        highlighters=[h_val_pos, h_val_neg],
        formatters=[formatter],
        compact_printing=true,
        fit_table_in_display_vertically=false,
    )
end

# --------------- Account ---------------

function Base.show(
    io::IO,
    acc::Account{TTime}
    ;
    max_trades=30,
    kwargs...
) where {TTime<:Dates.AbstractTime}
    display_width = displaysize(io)[2]

    function get_color(val)
        val >= 0 && return val == 0 ? crayon"#888888" : crayon"#11BF11"
        crayon"#DD0000"
    end

    title = " ACCOUNT SUMMARY "
    title_line = '━'^(floor(Int64, (display_width - length(title)) / 2))
    println(io, title_line * title * title_line)
    print(io, "\033[1mCash balances\033[0m ($(length(acc.ledger.balances)))\n")
    print_cash_balances(io, acc; kwargs...)
    print(io, "\n")
    print(io, "\033[1mEquity balances\033[0m ($(length(acc.ledger.equities)))\n")
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
