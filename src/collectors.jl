import Base: values
using Dates
using EnumX

# ----------------------------------------------------------

mutable struct PeriodicValues{T,TPeriod<:Period,TTime}
    const dates::Vector{TTime}
    const values::Vector{T}
    const period::TPeriod
    last_dt::TTime
end

@inline dates(pv::PeriodicValues) = pv.dates
@inline Base.values(pv::PeriodicValues) = pv.values

function periodic_collector(::Type{T}, period::TPeriod; time_type::Type{TTime}=DateTime) where {T,TPeriod<:Period,TTime}
    dates = Vector{TTime}()
    values = Vector{T}()
    # Create initial timestamp with appropriate type
    init_dt = if TTime <: DateTime
        DateTime(0)
    else
        # For NanoDate or other time types, use a very early date
        TTime(1900, 1, 1)
    end
    pv = PeriodicValues(dates, values, period, init_dt)

    @inline function collector(dt::TTime, value::T)
        if (dt - pv.last_dt) >= period
            push!(dates, dt)
            push!(values, value)
            pv.last_dt = dt
        end
        return
    end

    collector, pv
end


@inline function should_collect(pv::PeriodicValues{T,TPeriod,TTime}, dt) where {T,TPeriod<:Period,TTime}
    (dt - pv.last_dt) >= pv.period
end

# ----------------------------------------------------------

mutable struct PredicateValues{T,TPredicate<:Function,TTime}
    const dates::Vector{TTime}
    const values::Vector{T}
    const predicate::TPredicate
    last_dt::TTime
    last_value::T
end

@inline dates(pv::PredicateValues) = pv.dates
@inline Base.values(pv::PredicateValues) = pv.values

function predicate_collector(::Type{T}, predicate::TPredicate, init_value::T; time_type::Type{TTime}=DateTime) where {T,TPredicate<:Function,TTime}
    dates = Vector{TTime}()
    values = Vector{T}()
    # Create initial timestamp with appropriate type
    init_dt = if TTime <: DateTime
        DateTime(0)
    else
        # For NanoDate or other time types, use a very early date
        TTime(1900, 1, 1)
    end
    pv = PredicateValues(dates, values, predicate, init_dt, init_value)

    @inline function collector(dt::TTime, value::T)
        if predicate(pv, dt)
            push!(dates, dt)
            push!(values, value)
            pv.last_dt = dt
            pv.last_value = value
        end
        return
    end

    collector, pv
end


@inline function should_collect(pv::PredicateValues{T,TPredicate,TTime}, dt) where {T,TPredicate<:Function,TTime}
    pv.predicate(pv, dt)
end

# ----------------------------------------------------------

mutable struct MinValue{T,TTime}
    dt::TTime
    min_value::T
end

function min_value_collector(::Type{T}; time_type::Type{TTime}=DateTime) where {T,TTime}
    # Create initial timestamp with appropriate type
    init_dt = if TTime <: DateTime
        DateTime(0)
    else
        # For NanoDate or other time types, use a very early date
        TTime(1900, 1, 1)
    end
    mv = MinValue{T,TTime}(init_dt, typemax(T))

    @inline function collector(dt::TTime, value::T)
        if value < mv.min_value
            mv.min_value = value
            mv.dt = dt
        end
        return
    end

    collector, mv
end


# ----------------------------------------------------------

mutable struct MaxValue{T,TTime}
    dt::TTime
    max_value::T
end

function max_value_collector(::Type{T}; time_type::Type{TTime}=DateTime) where {T,TTime}
    # Create initial timestamp with appropriate type
    init_dt = if TTime <: DateTime
        DateTime(0)
    else
        # For NanoDate or other time types, use a very early date
        TTime(1900, 1, 1)
    end
    mv = MaxValue{T,TTime}(init_dt, typemin(T))

    @inline function collector(dt::TTime, value::T)
        if value > mv.max_value
            mv.max_value = value
            mv.dt = dt
        end
        return
    end

    collector, mv
end


# ----------------------------------------------------------

@enumx DrawdownMode::Int8 Percentage = 1 PnL = 2

mutable struct DrawdownValues{TTime}
    const dates::Vector{TTime}
    const values::Vector{Price}
    const mode::DrawdownMode.T
    max_equity::Price
    last_dt::TTime
end

@inline dates(pv::DrawdownValues) = pv.dates
@inline Base.values(pv::DrawdownValues) = pv.values

function drawdown_collector(mode::DrawdownMode.T, interval::Dates.Period; time_type::Type{TTime}=DateTime) where {TTime}
    drawdown_collector(mode, (v, dt, equity) -> dt - v.last_dt >= interval; time_type=time_type)
end


function drawdown_collector(mode::DrawdownMode.T, predicate::TFunc; time_type::Type{TTime}=DateTime) where {TFunc<:Function,TTime}
    dates = Vector{TTime}()
    values = Vector{Price}()
    # Create initial timestamp with appropriate type
    init_dt = if TTime <: DateTime
        DateTime(0)
    else
        # For NanoDate or other time types, use a very early date
        TTime(1900, 1, 1)
    end
    dv = DrawdownValues{TTime}(
        dates,
        values,
        mode,
        -Inf,
        init_dt)

    @inline function collector(dt::TTime, equity::Price)
        # keep track of max equity value
        dv.max_equity = max(dv.max_equity, equity)

        # should collect new drawdown value?
        if predicate(dv, dt, equity)
            drawdown = min(0.0, equity - dv.max_equity)
            if mode == DrawdownMode.Percentage
                drawdown /= dv.max_equity
            end
            push!(dates, dt)
            push!(values, drawdown)
            dv.last_dt = dt
        end

        return
    end

    collector, dv
end


# ----------------------------------------------------------
