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
        Dict(:name => "Symbol", :val => t -> t.order.inst.spec.symbol, :fmt => (t, v) -> v),
        # Dict(:name => "Date", :val => t -> "$(format_datetime(acc, t.order.date)) +$(Dates.value(round(t.date - t.order.date, Millisecond))) ms", :fmt => (e, v) -> v),
        Dict(:name => "Date", :val => t -> "$(format_datetime(acc, t.date))", :fmt => (e, v) -> v),
        Dict(:name => "Qty", :val => t -> t.order.quantity, :fmt => (t, v) -> format_base(t.order.inst, v)),
        Dict(:name => "Filled", :val => t -> t.fill_qty, :fmt => (t, v) -> format_base(t.order.inst, v)),
        # Dict(:name => "Remain. qty", :val => t -> t.remaining_qty, :fmt => (t, v) -> format_base(t.order.inst, v)),
        Dict(:name => "Price", :val => t -> t.fill_price, :fmt => (t, v) -> isnan(v) ? "—" : format_quote(t.order.inst, v)),
        Dict(:name => "TP", :val => t -> t.order.take_profit, :fmt => (t, v) -> isnan(v) ? "—" : format_quote(t.order.inst, v)),
        Dict(:name => "SL", :val => t -> t.order.stop_loss, :fmt => (t, v) -> isnan(v) ? "—" : format_quote(t.order.inst, v)),
        Dict(:name => "Ccy", :val => t -> t.order.inst.spec.settle_symbol, :fmt => (t, v) -> v),
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

    _print_record_table(
        io,
        trades,
        cols
        ;
        max_rows=max_print,
        value_columns=("Fill P&L", "Return (gross)", "Return (net)"),
        quantity_columns=("Filled",),
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
        Dict(:name => "Inst", :val => cf -> cf.inst_index, :fmt => (cf, v) -> v == 0 ? "—" : string(positions[v].inst.spec.symbol)),
    ]

    _print_record_table(
        io,
        flows,
        cols
        ;
        max_rows=max_print,
        value_columns=("Amount",),
        quantity_columns=(),
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
        Dict(:name => "Symbol", :val => t -> t.inst.spec.symbol, :fmt => (p, v) -> v),
        Dict(:name => "Qty", :val => t -> t.quantity, :fmt => (p, v) -> format_base(p.inst, v)),
        Dict(:name => "Entry px", :val => t -> t.avg_entry_price, :fmt => (p, v) -> isnan(v) ? "—" : format_quote(p.inst, v)),
        Dict(:name => "Ccy", :val => t -> t.inst.spec.quote_symbol, :fmt => (p, v) -> v),
        Dict(:name => "P&L", :val => t -> t.pnl_quote, :fmt => (p, v) -> isnan(v) ? "—" : format_quote(p.inst, v)),
    ]

    _print_record_table(
        io,
        positions,
        cols
        ;
        max_rows=max_print,
        value_columns=("P&L",),
        quantity_columns=("Qty",),
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
    _print_record_table(
        io,
        acc.ledger.cash,
        cols
        ;
        max_rows=-1,
        value_columns=("Value",),
        quantity_columns=(),
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
    _print_record_table(
        io,
        acc.ledger.cash,
        cols
        ;
        max_rows=-1,
        value_columns=("Value",),
        quantity_columns=(),
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
    display_width = max(0, displaysize(io)[2])

    title = " ACCOUNT SUMMARY "
    title_line = '━'^max(0, fld(display_width - textwidth(title), 2))
    println(io, _clip_table_text(title_line * title * title_line, display_width))
    _print_styled(io, "Cash balances"; bold=true)
    println(io, " ($(length(acc.ledger.balances)))")
    print_cash_balances(io, acc; kwargs...)
    print(io, "\n")
    _print_styled(io, "Equity balances"; bold=true)
    println(io, " ($(length(acc.ledger.equities)))")
    print_equity_balances(io, acc; kwargs...)
    print(io, "\n")
    _print_styled(io, "Positions"; bold=true)
    println(io, " ($(count(has_exposure.(acc.positions))))")
    print_positions(io, acc; kwargs...)
    print(io, "\n")
    _print_styled(io, "Trades"; bold=true)
    println(io, " ($(length(acc.trades)))")
    print_trades(io, acc; max_print=max_trades, kwargs...)
    println(io, '━'^display_width)
    print(io, "")
end

Base.show(acc::Account; kwargs...) = Base.show(stdout, acc; kwargs...)
