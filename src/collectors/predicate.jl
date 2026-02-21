import Base: values
using Dates
import Tables

mutable struct PredicateValues{TTime<:Dates.AbstractTime,T,TPredicate<:Function}
    const dates::Vector{TTime}
    const values::Vector{T}
    const predicate::TPredicate
    last_dt::TTime
    last_value::T
end

@inline dates(pv::PredicateValues) = pv.dates
@inline Base.values(pv::PredicateValues) = pv.values

"""
Create a predicate-based collector and its storage container.
Returns a tuple of (collector_function, PredicateValues).
"""
function predicate_collector(
    ::Type{T},
    predicate::TPredicate,
    init_value::T
    ;
    time_type::Type{TTime}=DateTime
) where {T,TPredicate<:Function,TTime<:Dates.AbstractTime}
    dates = Vector{TTime}()
    values = Vector{T}()
    pv = PredicateValues{TTime,T,TPredicate}(
        dates,
        values,
        predicate,
        time_type(0),
        init_value
    )

    @inline function collector(dt::TTime, value::T)
        push!(dates, dt)
        push!(values, value)
        pv.last_dt = dt
        pv.last_value = value
        return
    end

    collector, pv
end

"""
Return `true` when a predicate collector should emit a new sample.
"""
@inline function should_collect(
    collector::PredicateValues{TTime,T,TPredicate},
    dt::TTime
) where {TTime<:Dates.AbstractTime,T,TPredicate<:Function}
    collector.predicate(collector, dt)
end

Tables.istable(::Type{PredicateValues{TTime,T,TPredicate}}) where {TTime<:Dates.AbstractTime,T,TPredicate} = true
Tables.rowaccess(::Type{PredicateValues{TTime,T,TPredicate}}) where {TTime<:Dates.AbstractTime,T,TPredicate} = true

Tables.schema(::PredicateValues{TTime,T,TPredicate}) where {TTime<:Dates.AbstractTime,T,TPredicate} = Tables.Schema((:date, :value), (TTime, T))

struct PredicateCollectorRows{TTime<:Dates.AbstractTime,T}
    dates::Vector{TTime}
    values::Vector{T}
end

Tables.rows(pv::PredicateValues{TTime,T,TPredicate}) where {TTime<:Dates.AbstractTime,T,TPredicate} = PredicateCollectorRows{TTime,T}(dates(pv), Base.values(pv))

Base.length(iter::PredicateCollectorRows) = length(iter.dates)

function Base.iterate(iter::PredicateCollectorRows{TTime,T}, idx::Int=1) where {TTime<:Dates.AbstractTime,T}
    idx > length(iter.dates) && return nothing
    date_ = @inbounds iter.dates[idx]
    value = @inbounds iter.values[idx]
    row = (date=date_, value=value)
    return row, idx + 1
end
