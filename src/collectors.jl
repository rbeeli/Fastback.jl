import Base: values
using Dates
using EnumX

# ----------------------------------------------------------

mutable struct PeriodicValues{TTime<:Dates.AbstractTime,T,TPeriod<:Period}
    const dates::Vector{TTime}
    const values::Vector{T}
    const period::TPeriod
    const init_value::TTime
    last_dt::TTime
end

@inline dates(pv::PeriodicValues) = pv.dates
@inline Base.values(pv::PeriodicValues) = pv.values

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

@inline function should_collect(
    collector::PeriodicValues{TTime,T,TPeriod},
    dt::TTime
) where {TTime<:Dates.AbstractTime,T,TPeriod<:Period}
    # need init_value check, otherwise NanoDates.jl will crash when doing
    # (dt - last_dt if) on last_dt=NanoDate(0)
    collector.last_dt == collector.init_value || (dt - collector.last_dt) >= collector.period
end

# ----------------------------------------------------------

mutable struct PredicateValues{TTime<:Dates.AbstractTime,T,TPredicate<:Function}
    const dates::Vector{TTime}
    const values::Vector{T}
    const predicate::TPredicate
    last_dt::TTime
    last_value::T
end

@inline dates(pv::PredicateValues) = pv.dates
@inline Base.values(pv::PredicateValues) = pv.values

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

@inline function should_collect(
    collector::PredicateValues{TTime,T,TPredicate},
    dt::TTime
) where {TTime<:Dates.AbstractTime,T,TPredicate<:Function}
    collector.predicate(collector, dt)
end

# ----------------------------------------------------------

mutable struct MinValue{TTime<:Dates.AbstractTime,T}
    dt::TTime
    min_value::T
end

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

@inline function should_collect(
    collector::MaxValue{TTime,T},
    value::T
) where {TTime<:Dates.AbstractTime,T}
    value > collector.max_value
end

# ----------------------------------------------------------

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

@inline function should_collect(
    ::DrawdownValues{TTime,TPeriod},
    ::TTime
) where {TTime<:Dates.AbstractTime,TPeriod<:Period}
    # Always process drawdown updates so that maxima from intermediate samples
    # are accounted for even when results are emitted at a lower frequency.
    true
end

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

# ----------------------------------------------------------
