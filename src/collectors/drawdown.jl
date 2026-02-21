import Base: values
using Dates
using EnumX
import Tables

@enumx DrawdownMode::Int8 Percentage = 1 PnL = 2

mutable struct DrawdownValues{TTime<:Dates.AbstractTime,TPeriod<:Period}
    const dates::Vector{TTime}
    const values::Vector{Price}
    const period::TPeriod
    const mode::DrawdownMode.T
    max_equity::Price
    last_dt::TTime
end

@inline dates(pv::DrawdownValues) = pv.dates
@inline Base.values(pv::DrawdownValues) = pv.values

"""
Return `true` for drawdown collectors (they always process updates).
"""
@inline function should_collect(
    ::DrawdownValues{TTime,TPeriod},
    ::TTime
) where {TTime<:Dates.AbstractTime,TPeriod<:Period}
    # Always process drawdown updates so that maxima from intermediate samples
    # are accounted for even when results are emitted at a lower frequency.
    true
end

"""
Create a drawdown collector (percentage or P&L mode).
Returns a tuple of (collector_function, DrawdownValues).
"""
function drawdown_collector(
    mode::DrawdownMode.T,
    period::TPeriod
    ;
    time_type::Type{TTime}=DateTime
) where {TTime<:Dates.AbstractTime,TPeriod<:Period}
    dates = Vector{TTime}()
    values = Vector{Price}()
    dv = DrawdownValues{TTime,TPeriod}(
        dates,
        values,
        period,
        mode,
        NaN,
        time_type(0))

    @inline function collector(dt::TTime, equity::Price)
        # keep track of max equity value
        dv.max_equity = !isfinite(dv.max_equity) ? equity : max(dv.max_equity, equity)
        drawdown = min(0.0, equity - dv.max_equity)
        if mode == DrawdownMode.Percentage
            drawdown /= dv.max_equity
        end

        should_emit = isempty(dates) || (dt - dv.last_dt) >= dv.period
        if should_emit
            push!(dates, dt)
            push!(values, drawdown)
            dv.last_dt = dt
        end
        return
    end

    collector, dv
end

# ----- Tables.jl ------

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
