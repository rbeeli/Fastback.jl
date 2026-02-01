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
        :side,
        :fill_price,
        :fill_qty,
        :remaining_qty,
        :take_profit,
        :stop_loss,
        :realized_pnl_settle,
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
        symbol=inst.symbol,
        side=trade_dir(t.fill_qty),
        fill_price=t.fill_price,
        fill_qty=t.fill_qty,
        remaining_qty=t.remaining_qty,
        take_profit=order.take_profit,
        stop_loss=order.stop_loss,
        realized_pnl_settle=t.realized_pnl_settle,
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
cashflows_table(acc::Account{TTime}) where {TTime<:Dates.AbstractTime} = CashflowsTable{TTime}(acc.cashflows, acc.cash)

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
        symbol=inst.symbol,
        qty=pos.quantity,
        avg_entry_price=pos.avg_entry_price,
        avg_settle_price=pos.avg_settle_price,
        pnl_quote=pos.pnl_quote,
        base_ccy=inst.base_symbol,
        quote_ccy=inst.quote_symbol,
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
        index=cash.index,
        symbol=cash.symbol,
        balance=balance,
        digits=cash.digits,
    )
    return row, idx + 1
end

"""
Return a Tables.jl view over account cash balances.
"""
balances_table(acc::Account) = CashBalancesTable(acc.cash, acc.balances)

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
        index=cash.index,
        symbol=cash.symbol,
        equity=equity_value,
        digits=cash.digits,
    )
    return row, idx + 1
end

"""
Return a Tables.jl view over account equities.
"""
equities_table(acc::Account) = EquityBalancesTable(acc.cash, acc.equities)

# -------------------------- Collectors -----------------------------------

## PeriodicValues

Tables.istable(::Type{PeriodicValues{TTime,T,TPeriod}}) where {TTime<:Dates.AbstractTime,T,TPeriod} = true
Tables.rowaccess(::Type{PeriodicValues{TTime,T,TPeriod}}) where {TTime<:Dates.AbstractTime,T,TPeriod} = true

Tables.schema(::PeriodicValues{TTime,T,TPeriod}) where {TTime<:Dates.AbstractTime,T,TPeriod} = Tables.Schema((:date, :value), (TTime, T))

Tables.istable(::Type{PredicateValues{TTime,T,TPredicate}}) where {TTime<:Dates.AbstractTime,T,TPredicate} = true
Tables.rowaccess(::Type{PredicateValues{TTime,T,TPredicate}}) where {TTime<:Dates.AbstractTime,T,TPredicate} = true

Tables.schema(::PredicateValues{TTime,T,TPredicate}) where {TTime<:Dates.AbstractTime,T,TPredicate} = Tables.Schema((:date, :value), (TTime, T))

struct CollectorRows{TTime<:Dates.AbstractTime,T}
    dates::Vector{TTime}
    values::Vector{T}
end

Tables.rows(pv::PeriodicValues{TTime,T,TPeriod}) where {TTime<:Dates.AbstractTime,T,TPeriod} = CollectorRows{TTime,T}(dates(pv), Base.values(pv))

Tables.rows(pv::PredicateValues{TTime,T,TPredicate}) where {TTime<:Dates.AbstractTime,T,TPredicate} = CollectorRows{TTime,T}(dates(pv), Base.values(pv))

Base.length(iter::CollectorRows) = length(iter.dates)

function Base.iterate(iter::CollectorRows{TTime,T}, idx::Int=1) where {TTime<:Dates.AbstractTime,T}
    idx > length(iter.dates) && return nothing
    date_ = @inbounds iter.dates[idx]
    value = @inbounds iter.values[idx]
    row = (date=date_, value=value)
    return row, idx + 1
end

# -----------------------------------------------------------------------------

## DrawdownValues

Tables.istable(::Type{DrawdownValues{TTime,TPeriod}}) where {TTime<:Dates.AbstractTime,TPeriod} = true
Tables.rowaccess(::Type{DrawdownValues{TTime,TPeriod}}) where {TTime<:Dates.AbstractTime,TPeriod} = true

Tables.schema(::DrawdownValues{TTime,TPeriod}) where {TTime<:Dates.AbstractTime,TPeriod} = Tables.Schema((:date, :drawdown), (TTime, Price))

struct DrawdownRows{TTime<:Dates.AbstractTime,TPeriod}
    dates::Vector{TTime}
    values::Vector{Price}
end

Tables.rows(dv::DrawdownValues{TTime,TPeriod}) where {TTime<:Dates.AbstractTime,TPeriod} = DrawdownRows{TTime,TPeriod}(dates(dv), Base.values(dv))

Base.length(iter::DrawdownRows) = length(iter.dates)

function Base.iterate(iter::DrawdownRows{TTime,TPeriod}, idx::Int=1) where {TTime<:Dates.AbstractTime,TPeriod}
    idx > length(iter.dates) && return nothing
    date_ = @inbounds iter.dates[idx]
    value = @inbounds iter.values[idx]
    row = (date=date_, drawdown=value)
    return row, idx + 1
end

# -----------------------------------------------------------------------------
