import Base: values
using Dates
using EnumX
import Tables

@enumx TurnoverMode::Int8 RoundTrip = 1 OneWay = 2

mutable struct TurnoverValues{TTime<:Dates.AbstractTime,TPeriod<:Period}
    const dates::Vector{TTime}
    const gross_traded_notionals::Vector{Price}
    const equities::Vector{Price}
    const turnovers::Vector{Price}
    const period::TPeriod
    const mode::TurnoverMode.T
    pending_gross_traded_notional::Price
    last_dt::TTime
    last_trade_index::Int
end

@inline dates(tv::TurnoverValues) = tv.dates
@inline Base.values(tv::TurnoverValues) = tv.turnovers

@inline function _turnover_denominator_scale(mode::TurnoverMode.T)::Price
    mode == TurnoverMode.RoundTrip ? 2.0 : 1.0
end

@inline function _turnover_value(
    gross_traded_notional::Price,
    equity_value::Price,
    mode::TurnoverMode.T,
)::Price
    equity_value <= 0.0 && return NaN
    gross_traded_notional / (_turnover_denominator_scale(mode) * equity_value)
end

"""
Return `true` for turnover collectors.

Turnover collectors process every update so newly recorded trades are absorbed
into the pending period even when rows are emitted at a lower frequency.
"""
@inline function should_collect(
    ::TurnoverValues{TTime,TPeriod},
    ::TTime,
) where {TTime<:Dates.AbstractTime,TPeriod<:Period}
    true
end

"""
Create a periodic account turnover collector.
Returns a tuple of (collector_function, TurnoverValues).

The collector tracks gross traded notional from newly recorded account trades
using each trade's fill-time base-currency notional, and emits turnover at
`period` intervals.

By default, `mode=TurnoverMode.RoundTrip`, turnover is:
`gross_traded_notional / (2 * equity_base_ccy(acc))`.

Use `mode=TurnoverMode.OneWay` to report one-way notional turnover:
`gross_traded_notional / equity_base_ccy(acc)`.

Turnover is `NaN` when account base-currency equity is nonpositive. The account
must have `track_trades=true`.
"""
function turnover_collector(
    acc::Account{TTime,TBroker},
    period::TPeriod;
    mode::TurnoverMode.T=TurnoverMode.RoundTrip,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker,TPeriod<:Period}
    acc.track_trades || throw(ArgumentError("turnover_collector requires account trade tracking (track_trades=true)."))

    dts = Vector{TTime}()
    gross_notionals = Vector{Price}()
    equities = Vector{Price}()
    turnovers = Vector{Price}()
    tv = TurnoverValues{TTime,TPeriod}(
        dts,
        gross_notionals,
        equities,
        turnovers,
        period,
        mode,
        zero(Price),
        TTime(0),
        length(acc.trades),
    )

    @inline function collector(dt::TTime)
        last_trade_index = length(acc.trades)
        gross_traded_notional = tv.pending_gross_traded_notional
        @inbounds for i in (tv.last_trade_index + 1):last_trade_index
            gross_traded_notional += acc.trades[i].notional_base
        end
        tv.last_trade_index = last_trade_index
        tv.pending_gross_traded_notional = gross_traded_notional

        should_emit = isempty(dts) || (dt - tv.last_dt) >= tv.period
        if should_emit
            equity_value = equity_base_ccy(acc)
            turnover = _turnover_value(gross_traded_notional, equity_value, mode)
            push!(dts, dt)
            push!(gross_notionals, gross_traded_notional)
            push!(equities, equity_value)
            push!(turnovers, turnover)
            tv.pending_gross_traded_notional = zero(Price)
            tv.last_dt = dt
        end
        return
    end

    collector, tv
end

# ----- Tables.jl ------

Tables.istable(::Type{TurnoverValues{TTime,TPeriod}}) where {TTime<:Dates.AbstractTime,TPeriod} = true
Tables.rowaccess(::Type{TurnoverValues{TTime,TPeriod}}) where {TTime<:Dates.AbstractTime,TPeriod} = true

Tables.schema(::TurnoverValues{TTime,TPeriod}) where {TTime<:Dates.AbstractTime,TPeriod} = Tables.Schema(
    (:date, :gross_traded_notional, :equity, :turnover, :mode),
    (TTime, Price, Price, Price, TurnoverMode.T),
)

struct TurnoverRows{TTime<:Dates.AbstractTime,TPeriod}
    tv::TurnoverValues{TTime,TPeriod}
end

Tables.rows(tv::TurnoverValues{TTime,TPeriod}) where {TTime<:Dates.AbstractTime,TPeriod} = TurnoverRows{TTime,TPeriod}(tv)

Base.length(iter::TurnoverRows{TTime,TPeriod}) where {TTime<:Dates.AbstractTime,TPeriod} = length(iter.tv.dates)

function Base.iterate(iter::TurnoverRows{TTime,TPeriod}, idx::Int=1) where {TTime<:Dates.AbstractTime,TPeriod}
    idx > length(iter.tv.dates) && return nothing
    tv = iter.tv
    date_ = @inbounds tv.dates[idx]
    gross_traded_notional = @inbounds tv.gross_traded_notionals[idx]
    equity_value = @inbounds tv.equities[idx]
    turnover = @inbounds tv.turnovers[idx]
    row = (
        date=date_,
        gross_traded_notional=gross_traded_notional,
        equity=equity_value,
        turnover=turnover,
        mode=tv.mode,
    )
    return row, idx + 1
end
