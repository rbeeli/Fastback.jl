import Base: values
using Dates
import Tables

mutable struct PeriodicValues{TTime<:Dates.AbstractTime,T,TPeriod<:Period}
    const dates::Vector{TTime}
    const values::Vector{T}
    const period::TPeriod
    const init_value::TTime
    last_dt::TTime
end

"""
Return the collected timestamps/dates.
"""
@inline dates(pv::PeriodicValues) = pv.dates

"""
Return the collected values.
"""
@inline Base.values(pv::PeriodicValues) = pv.values

"""
Create a periodic collector and its storage container.
Returns a tuple of (collector_function, PeriodicValues).
"""
function periodic_collector(
    ::Type{T},
    period::TPeriod
    ;
    time_type::Type{TTime}=DateTime
) where {T,TPeriod<:Period,TTime<:Dates.AbstractTime}
    dates = Vector{TTime}()
    values = Vector{T}()
    init_value = TTime(0)
    pv = PeriodicValues{TTime,T,TPeriod}(
        dates,
        values,
        period,
        init_value,
        init_value
    )

    @inline function collector(dt::TTime, value::T)
        push!(dates, dt)
        push!(values, value)
        pv.last_dt = dt
        return
    end

    collector, pv
end

"""
Return `true` when a periodic collector should emit a new sample.
"""
@inline function should_collect(
    collector::PeriodicValues{TTime,T,TPeriod},
    dt::TTime
) where {TTime<:Dates.AbstractTime,T,TPeriod<:Period}
    # need init_value check, otherwise NanoDates.jl will crash when doing
    # (dt - last_dt if) on last_dt=NanoDate(0)
    collector.last_dt == collector.init_value || (dt - collector.last_dt) >= collector.period
end

# ----- Tables.jl ------

Tables.istable(::Type{PeriodicValues{TTime,T,TPeriod}}) where {TTime<:Dates.AbstractTime,T,TPeriod} = true
Tables.rowaccess(::Type{PeriodicValues{TTime,T,TPeriod}}) where {TTime<:Dates.AbstractTime,T,TPeriod} = true

Tables.schema(::PeriodicValues{TTime,T,TPeriod}) where {TTime<:Dates.AbstractTime,T,TPeriod} = Tables.Schema((:date, :value), (TTime, T))

struct PeriodicCollectorRows{TTime<:Dates.AbstractTime,T}
    dates::Vector{TTime}
    values::Vector{T}
end

Tables.rows(pv::PeriodicValues{TTime,T,TPeriod}) where {TTime<:Dates.AbstractTime,T,TPeriod} = PeriodicCollectorRows{TTime,T}(dates(pv), Base.values(pv))

Base.length(iter::PeriodicCollectorRows) = length(iter.dates)

function Base.iterate(iter::PeriodicCollectorRows{TTime,T}, idx::Int=1) where {TTime<:Dates.AbstractTime,T}
    idx > length(iter.dates) && return nothing
    date_ = @inbounds iter.dates[idx]
    value = @inbounds iter.values[idx]
    row = (date=date_, value=value)
    return row, idx + 1
end
