using Dates
import Tables

# -----------------------------------------------------------------------------

"""
Provides a Tables.jl compatible view over the trades contained in an `Account` or
an arbitrary vector of `Trade`s.
"""
struct TradesTable{TTime<:Dates.AbstractTime}
    trades::Vector{Trade{TTime}}
end

Tables.istable(::Type{<:TradesTable}) = true
Tables.rowaccess(::Type{<:TradesTable}) = true

Tables.schema(::TradesTable{TTime}) where {TTime<:Dates.AbstractTime} = Tables.Schema(
    (
        :tid,
        :oid,
        :trade_date,
        :order_date,
        :symbol,
        :settlement_style,
        :side,
        :fill_price,
        :fill_qty,
        :remaining_qty,
        :take_profit,
        :stop_loss,
        :fill_pnl_settle,
        :realized_qty,
        :position_qty,
        :position_price,
        :commission_settle,
        :cash_delta_settle,
        :reason,
    ),
    (
        Int,
        Int,
        TTime,
        TTime,
        Symbol,
        SettlementStyle.T,
        TradeDir.T,
        Price,
        Quantity,
        Quantity,
        Price,
        Price,
        Price,
        Quantity,
        Quantity,
        Price,
        Price,
        Price,
        TradeReason.T,
    )
)

struct TradeRows{TTime<:Dates.AbstractTime}
    trades::Vector{Trade{TTime}}
end

Tables.rows(tbl::TradesTable{TTime}) where {TTime<:Dates.AbstractTime} = TradeRows{TTime}(tbl.trades)

Base.length(iter::TradeRows) = length(iter.trades)

function Base.iterate(iter::TradeRows{TTime}, idx::Int=1) where {TTime<:Dates.AbstractTime}
    idx > length(iter.trades) && return nothing
    t = @inbounds iter.trades[idx]
    order = t.order
    inst = order.inst
    row = (
        tid=t.tid,
        oid=order.oid,
        trade_date=t.date,
        order_date=order.date,
        symbol=inst.spec.symbol,
        settlement_style=inst.spec.settlement,
        side=trade_dir(t.fill_qty),
        fill_price=t.fill_price,
        fill_qty=t.fill_qty,
        remaining_qty=t.remaining_qty,
        take_profit=order.take_profit,
        stop_loss=order.stop_loss,
        fill_pnl_settle=t.fill_pnl_settle,
        realized_qty=t.realized_qty,
        position_qty=t.pos_qty,
        position_price=t.pos_price,
        commission_settle=t.commission_settle,
        cash_delta_settle=t.cash_delta_settle,
        reason=t.reason,
    )
    return row, idx + 1
end

"""
Return a Tables.jl view over account trades.
"""
trades_table(acc::Account{TTime}) where {TTime<:Dates.AbstractTime} = TradesTable{TTime}(acc.trades)

# -----------------------------------------------------------------------------

"""
Provides a Tables.jl compatible view over the cashflows contained in an `Account`.
"""
struct CashflowsTable{TTime<:Dates.AbstractTime}
    cashflows::Vector{Cashflow{TTime}}
    cash::Vector{Cash}
end

Tables.istable(::Type{<:CashflowsTable}) = true
Tables.rowaccess(::Type{<:CashflowsTable}) = true

Tables.schema(::CashflowsTable{TTime}) where {TTime<:Dates.AbstractTime} = Tables.Schema(
    (
        :id,
        :date,
        :kind,
        :cash_symbol,
        :amount,
        :inst_index,
    ),
    (
        Int,
        TTime,
        CashflowKind.T,
        Symbol,
        Price,
        Int,
    )
)

struct CashflowRows{TTime<:Dates.AbstractTime}
    cashflows::Vector{Cashflow{TTime}}
    cash::Vector{Cash}
end

Tables.rows(tbl::CashflowsTable{TTime}) where {TTime<:Dates.AbstractTime} = CashflowRows{TTime}(tbl.cashflows, tbl.cash)

Base.length(iter::CashflowRows) = length(iter.cashflows)

function Base.iterate(iter::CashflowRows{TTime}, idx::Int=1) where {TTime<:Dates.AbstractTime}
    idx > length(iter.cashflows) && return nothing
    cf = @inbounds iter.cashflows[idx]
    cash = iter.cash
    cash_symbol = @inbounds cash[cf.cash_index].symbol
    row = (
        id=cf.id,
        date=cf.dt,
        kind=cf.kind,
        cash_symbol=cash_symbol,
        amount=cf.amount,
        inst_index=cf.inst_index,
    )
    return row, idx + 1
end

"""
Return a Tables.jl view over account cashflows.
"""
cashflows_table(acc::Account{TTime}) where {TTime<:Dates.AbstractTime} = CashflowsTable{TTime}(acc.cashflows, acc.ledger.cash)

# -----------------------------------------------------------------------------

"""
Provides a Tables.jl compatible view over the positions contained in an `Account` or
an arbitrary vector of `Position`s.
"""
struct PositionsTable{TTime<:Dates.AbstractTime}
    positions::Vector{Position{TTime}}
end

Tables.istable(::Type{<:PositionsTable}) = true
Tables.rowaccess(::Type{<:PositionsTable}) = true

Tables.schema(::PositionsTable{TTime}) where {TTime<:Dates.AbstractTime} = Tables.Schema(
    (
        :index,
        :symbol,
        :qty,
        :avg_entry_price,
        :avg_settle_price,
        :pnl_quote,
        :base_ccy,
        :quote_ccy,
        :last_oid,
        :last_tid,
    ),
    (
        Int,
        Symbol,
        Quantity,
        Price,
        Price,
        Price,
        Symbol,
        Symbol,
        Int,
        Int,
    )
)

struct PositionRows{TTime<:Dates.AbstractTime}
    positions::Vector{Position{TTime}}
end

Tables.rows(tbl::PositionsTable{TTime}) where {TTime<:Dates.AbstractTime} = PositionRows{TTime}(tbl.positions)

Base.length(iter::PositionRows) = length(iter.positions)

function Base.iterate(iter::PositionRows{TTime}, idx::Int=1) where {TTime<:Dates.AbstractTime}
    idx > length(iter.positions) && return nothing
    pos = @inbounds iter.positions[idx]
    inst = pos.inst
    row = (
        index=pos.index,
        symbol=inst.spec.symbol,
        qty=pos.quantity,
        avg_entry_price=pos.avg_entry_price,
        avg_settle_price=pos.avg_settle_price,
        pnl_quote=pos.pnl_quote,
        base_ccy=inst.spec.base_symbol,
        quote_ccy=inst.spec.quote_symbol,
        last_oid=isnothing(pos.last_order) ? 0 : pos.last_order.oid,
        last_tid=isnothing(pos.last_trade) ? 0 : pos.last_trade.tid,
    )
    return row, idx + 1
end

"""
Return a Tables.jl view over account positions.
"""
positions_table(acc::Account{TTime}) where {TTime<:Dates.AbstractTime} = PositionsTable{TTime}(acc.positions)

# -----------------------------------------------------------------------------

"""
Provides a Tables.jl compatible view over the cash balances contained in an `Account` or
an arbitrary vector of `Cash`es.
"""
struct CashBalancesTable
    cash::Vector{Cash}
    balances::Vector{Price}
end

Tables.istable(::Type{<:CashBalancesTable}) = true
Tables.rowaccess(::Type{<:CashBalancesTable}) = true

Tables.schema(::CashBalancesTable) = Tables.Schema(
    (:index, :symbol, :balance, :digits),
    (Int, Symbol, Price, Int)
)

struct CashBalanceRows
    cash::Vector{Cash}
    balances::Vector{Price}
end

Tables.rows(tbl::CashBalancesTable) = CashBalanceRows(tbl.cash, tbl.balances)

Base.length(iter::CashBalanceRows) = length(iter.cash)

function Base.iterate(iter::CashBalanceRows, idx::Int=1)
    idx > length(iter.cash) && return nothing
    cash = @inbounds iter.cash[idx]
    balance = @inbounds iter.balances[idx]
    row = (
        index=idx,
        symbol=cash.symbol,
        balance=balance,
        digits=cash.digits,
    )
    return row, idx + 1
end

"""
Return a Tables.jl view over account cash balances.
"""
balances_table(acc::Account) = CashBalancesTable(acc.ledger.cash, acc.ledger.balances)

# -----------------------------------------------------------------------------

"""
Provides a Tables.jl compatible view over the equity balances contained in an `Account` or
an arbitrary vector of `Cash`es.
"""
struct EquityBalancesTable
    cash::Vector{Cash}
    equities::Vector{Price}
end

Tables.istable(::Type{<:EquityBalancesTable}) = true
Tables.rowaccess(::Type{<:EquityBalancesTable}) = true

Tables.schema(::EquityBalancesTable) = Tables.Schema(
    (:index, :symbol, :equity, :digits),
    (Int, Symbol, Price, Int)
)

struct EquityBalanceRows
    cash::Vector{Cash}
    equities::Vector{Price}
end

Tables.rows(tbl::EquityBalancesTable) = EquityBalanceRows(tbl.cash, tbl.equities)

Base.length(iter::EquityBalanceRows) = length(iter.cash)

function Base.iterate(iter::EquityBalanceRows, idx::Int=1)
    idx > length(iter.cash) && return nothing
    cash = @inbounds iter.cash[idx]
    equity_value = @inbounds iter.equities[idx]
    row = (
        index=idx,
        symbol=cash.symbol,
        equity=equity_value,
        digits=cash.digits,
    )
    return row, idx + 1
end

"""
Return a Tables.jl view over account equities.
"""
equities_table(acc::Account) = EquityBalancesTable(acc.ledger.cash, acc.ledger.equities)

# -----------------------------------------------------------------------------

struct PnlConcentrationRows
    table::PnlConcentrationTable
end

struct PerformanceSummaryRows
    summary::PerformanceSummary
end

const _PERFORMANCE_SUMMARY_TABLE_NAMES = (
    :tot_ret,
    :cagr,
    :sharpe,
    :sortino,
    :calmar,
    :max_dd,
    :avg_dd,
    :ulcer,
    :vol,
    :n_periods,
    :best_ret,
    :worst_ret,
    :positive_period_rate,
    :expected_shortfall_95,
    :skewness,
    :kurtosis,
    :downside_vol,
    :max_dd_duration,
    :pct_time_in_drawdown,
    :omega,
    :n_trades,
    :n_closing_trades,
    :winners,
    :losers,
)

const _PERFORMANCE_SUMMARY_TABLE_TYPES = (
    Float64,
    Float64,
    Float64,
    Float64,
    Float64,
    Float64,
    Float64,
    Float64,
    Float64,
    Int,
    Float64,
    Float64,
    Float64,
    Float64,
    Float64,
    Float64,
    Float64,
    Int,
    Float64,
    Float64,
    Int,
    Int,
    Union{Missing,Float64},
    Union{Missing,Float64},
)

const _PNL_CONCENTRATION_TABLE_NAMES = (
    :bucket,
    :quote_symbol,
    :realized_trade_count,
    :gross_realized_pnl_quote,
    :net_realized_pnl_quote,
    :share_of_abs_pnl,
    :share_of_net_pnl,
)

const _PNL_CONCENTRATION_TABLE_TYPES = (
    PnlConcentrationBucket,
    Symbol,
    Int,
    Price,
    Price,
    Float64,
    Float64,
)

Tables.istable(::Type{PnlConcentrationTable}) = true
Tables.rowaccess(::Type{PnlConcentrationTable}) = true
Tables.columnaccess(::Type{PnlConcentrationTable}) = true
Tables.rows(tbl::PnlConcentrationTable) = PnlConcentrationRows(tbl)
Tables.schema(::PnlConcentrationTable) = Tables.Schema(
    _PNL_CONCENTRATION_TABLE_NAMES,
    _PNL_CONCENTRATION_TABLE_TYPES,
)
Tables.columns(tbl::PnlConcentrationTable) = (
    bucket=tbl.bucket,
    quote_symbol=tbl.quote_symbol,
    realized_trade_count=tbl.realized_trade_count,
    gross_realized_pnl_quote=tbl.gross_realized_pnl_quote,
    net_realized_pnl_quote=tbl.net_realized_pnl_quote,
    share_of_abs_pnl=tbl.share_of_abs_pnl,
    share_of_net_pnl=tbl.share_of_net_pnl,
)

Base.length(tbl::PnlConcentrationTable) = length(tbl.bucket)
Base.length(rows::PnlConcentrationRows) = length(rows.table)
Base.size(tbl::PnlConcentrationTable) = (length(tbl), length(_PNL_CONCENTRATION_TABLE_NAMES))
Base.size(tbl::PnlConcentrationTable, dim::Integer) = dim == 1 ? length(tbl) :
    dim == 2 ? length(_PNL_CONCENTRATION_TABLE_NAMES) :
    1

function Base.iterate(rows::PnlConcentrationRows, idx::Int=1)
    tbl = rows.table
    idx > length(tbl) && return nothing
    row = (
        bucket=@inbounds(tbl.bucket[idx]),
        quote_symbol=@inbounds(tbl.quote_symbol[idx]),
        realized_trade_count=@inbounds(tbl.realized_trade_count[idx]),
        gross_realized_pnl_quote=@inbounds(tbl.gross_realized_pnl_quote[idx]),
        net_realized_pnl_quote=@inbounds(tbl.net_realized_pnl_quote[idx]),
        share_of_abs_pnl=@inbounds(tbl.share_of_abs_pnl[idx]),
        share_of_net_pnl=@inbounds(tbl.share_of_net_pnl[idx]),
    )
    return row, idx + 1
end

Tables.istable(::Type{PerformanceSummaryTable}) = true
Tables.rowaccess(::Type{PerformanceSummaryTable}) = true
Tables.rows(tbl::PerformanceSummaryTable) = PerformanceSummaryRows(tbl.summary)
Tables.schema(::PerformanceSummaryTable) = Tables.Schema(
    _PERFORMANCE_SUMMARY_TABLE_NAMES,
    _PERFORMANCE_SUMMARY_TABLE_TYPES,
)

Base.length(::PerformanceSummaryTable) = 1
Base.length(::PerformanceSummaryRows) = 1
Base.size(::PerformanceSummaryTable) = (1, length(_PERFORMANCE_SUMMARY_TABLE_NAMES))
Base.size(::PerformanceSummaryTable, dim::Integer) = dim == 1 ? 1 :
    dim == 2 ? length(_PERFORMANCE_SUMMARY_TABLE_NAMES) :
    1

function Base.iterate(rows::PerformanceSummaryRows, idx::Int=1)
    idx > 1 && return nothing
    return _performance_summary_table_row(rows.summary), 2
end

function _performance_summary_table_row(summary::PerformanceSummary)
    (
        tot_ret=summary.tot_ret,
        cagr=summary.cagr,
        sharpe=summary.sharpe,
        sortino=summary.sortino,
        calmar=summary.calmar,
        max_dd=summary.max_dd,
        avg_dd=summary.avg_dd,
        ulcer=summary.ulcer,
        vol=summary.vol,
        n_periods=summary.n_periods,
        best_ret=summary.best_ret,
        worst_ret=summary.worst_ret,
        positive_period_rate=summary.positive_period_rate,
        expected_shortfall_95=summary.expected_shortfall_95,
        skewness=summary.skewness,
        kurtosis=summary.kurtosis,
        downside_vol=summary.downside_vol,
        max_dd_duration=summary.max_dd_duration,
        pct_time_in_drawdown=summary.pct_time_in_drawdown,
        omega=summary.omega,
        n_trades=summary.n_trades,
        n_closing_trades=summary.n_closing_trades,
        winners=summary.winners,
        losers=summary.losers,
    )
end
