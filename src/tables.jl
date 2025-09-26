using Dates
import Tables

@inline maybe_with_nothing(::Type{Nothing}) = Nothing
@inline maybe_with_nothing(::Type{T}) where {T} = Union{Nothing,T}

# -----------------------------------------------------------------------------

"""
Provides a Tables.jl compatible view over the trades contained in an `Account` or
an arbitrary vector of `Trade`s.
"""
struct TradesTable{OData,IData}
    trades::Vector{Trade{OData,IData}}
end

Tables.istable(::Type{<:TradesTable}) = true
Tables.rowaccess(::Type{<:TradesTable}) = true

Tables.schema(::TradesTable{OData,IData}) where {OData,IData} = Tables.Schema(
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
        :realized_pnl,
        :realized_qty,
        :position_qty,
        :position_price,
        :commission,
        :order_metadata
    ),
    (
        Int,
        Int,
        DateTime,
        DateTime,
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
        maybe_with_nothing(OData)
    )
)

struct TradeRows{OData,IData}
    trades::Vector{Trade{OData,IData}}
end

Tables.rows(tbl::TradesTable{OData,IData}) where {OData,IData} = TradeRows{OData,IData}(tbl.trades)

Base.length(iter::TradeRows) = length(iter.trades)

function Base.iterate(iter::TradeRows{OData,IData}, idx::Int=1) where {OData,IData}
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
        realized_pnl=t.realized_pnl,
        realized_qty=t.realized_qty,
        position_qty=t.pos_qty,
        position_price=t.pos_price,
        commission=t.commission,
        order_metadata=order.metadata,
    )
    return row, idx + 1
end

trades_table(acc::Account{OData,IData,CData}) where {OData,IData,CData} = TradesTable{OData,IData}(acc.trades)

# -----------------------------------------------------------------------------

"""
Provides a Tables.jl compatible view over the positions contained in an `Account` or
an arbitrary vector of `Position`s.
"""
struct PositionsTable{OData,IData}
    positions::Vector{Position{OData,IData}}
end

Tables.istable(::Type{<:PositionsTable}) = true
Tables.rowaccess(::Type{<:PositionsTable}) = true

Tables.schema(::PositionsTable{OData,IData}) where {OData,IData} = Tables.Schema(
    (
        :index,
        :symbol,
        :qty,
        :avg_price,
        :pnl_local,
        :base_ccy,
        :quote_ccy,
    ),
    (
        UInt,
        Symbol,
        Quantity,
        Price,
        Price,
        Symbol,
        Symbol,
    )
)

struct PositionRows{OData,IData}
    positions::Vector{Position{OData,IData}}
end

Tables.rows(tbl::PositionsTable{OData,IData}) where {OData,IData} = PositionRows{OData,IData}(tbl.positions)

Base.length(iter::PositionRows) = length(iter.positions)

function Base.iterate(iter::PositionRows{OData,IData}, idx::Int=1) where {OData,IData}
    idx > length(iter.positions) && return nothing
    pos = @inbounds iter.positions[idx]
    inst = pos.inst
    row = (
        index=pos.index,
        symbol=inst.symbol,
        qty=pos.quantity,
        avg_price=pos.avg_price,
        pnl_local=pos.pnl_local,
        base_ccy=inst.base_symbol,
        quote_ccy=inst.quote_symbol,
    )
    return row, idx + 1
end

positions_table(acc::Account{OData,IData,CData}) where {OData,IData,CData} = PositionsTable{OData,IData}(acc.positions)

# -----------------------------------------------------------------------------

"""
Provides a Tables.jl compatible view over the cash balances contained in an `Account` or
an arbitrary vector of `Cash`es.
"""
struct CashBalancesTable{CData}
    cash::Vector{Cash{CData}}
    balances::Vector{Price}
end

Tables.istable(::Type{<:CashBalancesTable}) = true
Tables.rowaccess(::Type{<:CashBalancesTable}) = true

Tables.schema(::CashBalancesTable{CData}) where {CData} = Tables.Schema(
    (:index, :symbol, :balance, :digits, :metadata),
    (UInt, Symbol, Price, Int, maybe_with_nothing(CData))
)

struct CashBalanceRows{CData}
    cash::Vector{Cash{CData}}
    balances::Vector{Price}
end

Tables.rows(tbl::CashBalancesTable{CData}) where {CData} = CashBalanceRows{CData}(tbl.cash, tbl.balances)

Base.length(iter::CashBalanceRows) = length(iter.cash)

function Base.iterate(iter::CashBalanceRows{CData}, idx::Int=1) where {CData}
    idx > length(iter.cash) && return nothing
    cash = @inbounds iter.cash[idx]
    balance = @inbounds iter.balances[idx]
    row = (
        index=cash.index,
        symbol=cash.symbol,
        balance=balance,
        digits=cash.digits,
        metadata=cash.data,
    )
    return row, idx + 1
end

balances_table(acc::Account{OData,IData,CData}) where {OData,IData,CData} = CashBalancesTable{CData}(acc.cash, acc.balances)

# -----------------------------------------------------------------------------

"""
Provides a Tables.jl compatible view over the equity balances contained in an `Account` or
an arbitrary vector of `Cash`es.
"""
struct EquityBalancesTable{CData}
    cash::Vector{Cash{CData}}
    equities::Vector{Price}
end

Tables.istable(::Type{<:EquityBalancesTable}) = true
Tables.rowaccess(::Type{<:EquityBalancesTable}) = true

Tables.schema(::EquityBalancesTable{CData}) where {CData} = Tables.Schema(
    (:index, :symbol, :equity, :digits, :metadata),
    (UInt, Symbol, Price, Int, maybe_with_nothing(CData))
)

struct EquityBalanceRows{CData}
    cash::Vector{Cash{CData}}
    equities::Vector{Price}
end

Tables.rows(tbl::EquityBalancesTable{CData}) where {CData} = EquityBalanceRows{CData}(tbl.cash, tbl.equities)

Base.length(iter::EquityBalanceRows) = length(iter.cash)

function Base.iterate(iter::EquityBalanceRows{CData}, idx::Int=1) where {CData}
    idx > length(iter.cash) && return nothing
    cash = @inbounds iter.cash[idx]
    equity_value = @inbounds iter.equities[idx]
    row = (
        index=cash.index,
        symbol=cash.symbol,
        equity=equity_value,
        digits=cash.digits,
        metadata=cash.data,
    )
    return row, idx + 1
end

equities_table(acc::Account{OData,IData,CData}) where {OData,IData,CData} = EquityBalancesTable{CData}(acc.cash, acc.equities)

# -------------------------- Collectors -----------------------------------

## PeriodicValues

Tables.istable(::Type{PeriodicValues{T,TPeriod}}) where {T,TPeriod} = true
Tables.rowaccess(::Type{PeriodicValues{T,TPeriod}}) where {T,TPeriod} = true

Tables.schema(::PeriodicValues{T,TPeriod}) where {T,TPeriod} = Tables.Schema((:date, :value), (DateTime, T))

Tables.istable(::Type{PredicateValues{T,TPredicate}}) where {T,TPredicate} = true
Tables.rowaccess(::Type{PredicateValues{T,TPredicate}}) where {T,TPredicate} = true

Tables.schema(::PredicateValues{T,TPredicate}) where {T,TPredicate} = Tables.Schema((:date, :value), (DateTime, T))

struct CollectorRows{T}
    dates::Vector{DateTime}
    values::Vector{T}
end

Tables.rows(pv::PeriodicValues{T,TPeriod}) where {T,TPeriod} = CollectorRows{T}(dates(pv), Base.values(pv))

Tables.rows(pv::PredicateValues{T,TPredicate}) where {T,TPredicate} = CollectorRows{T}(dates(pv), Base.values(pv))

Base.length(iter::CollectorRows) = length(iter.dates)

function Base.iterate(iter::CollectorRows{T}, idx::Int=1) where {T}
    idx > length(iter.dates) && return nothing
    date_ = @inbounds iter.dates[idx]
    value = @inbounds iter.values[idx]
    row = (date=date_, value=value)
    return row, idx + 1
end

# -----------------------------------------------------------------------------

## DrawdownValues

Tables.istable(::Type{DrawdownValues}) = true
Tables.rowaccess(::Type{DrawdownValues}) = true

Tables.schema(::DrawdownValues) = Tables.Schema((:date, :drawdown), (DateTime, Price))

struct DrawdownRows
    dates::Vector{DateTime}
    values::Vector{Price}
end

Tables.rows(dv::DrawdownValues) = DrawdownRows(dates(dv), Base.values(dv))

Base.length(iter::DrawdownRows) = length(iter.dates)

function Base.iterate(iter::DrawdownRows, idx::Int=1)
    idx > length(iter.dates) && return nothing
    date_ = @inbounds iter.dates[idx]
    value = @inbounds iter.values[idx]
    row = (date=date_, drawdown=value)
    return row, idx + 1
end

# -----------------------------------------------------------------------------
