using Dates

mutable struct MinValue{TTime<:Dates.AbstractTime,T}
    dt::TTime
    min_value::T
end

"""
Create a collector that tracks the minimum observed value.
Returns a tuple of (collector_function, MinValue).
"""
function min_value_collector(
    ::Type{T}
    ;
    time_type::Type{TTime}=DateTime
) where {T,TTime<:Dates.AbstractTime}
    mv = MinValue{TTime,T}(time_type(0), typemax(T))

    @inline function collector(dt::TTime, value::T)
        mv.min_value = value
        mv.dt = dt
        return
    end

    collector, mv
end

"""
Return `true` when the current value is a new minimum.
"""
@inline function should_collect(
    collector::MinValue{TTime,T},
    value::T
) where {TTime<:Dates.AbstractTime,T}
    value < collector.min_value
end

# ----------------------------------------------------------

mutable struct MaxValue{TTime<:Dates.AbstractTime,T}
    dt::TTime
    max_value::T
end

"""
Create a collector that tracks the maximum observed value.
Returns a tuple of (collector_function, MaxValue).
"""
function max_value_collector(
    ::Type{T}
    ;
    time_type::Type{TTime}=DateTime
) where {T,TTime<:Dates.AbstractTime}
    mv = MaxValue{TTime,T}(time_type(0), typemin(T))

    @inline function collector(dt::TTime, value::T)
        mv.max_value = value
        mv.dt = dt
        return
    end

    collector, mv
end

"""
Return `true` when the current value is a new maximum.
"""
@inline function should_collect(
    collector::MaxValue{TTime,T},
    value::T
) where {TTime<:Dates.AbstractTime,T}
    value > collector.max_value
end
