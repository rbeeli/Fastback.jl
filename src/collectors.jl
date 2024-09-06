import Base: values
using Dates
using EnumX

# ----------------------------------------------------------

mutable struct PeriodicValues{T,TPeriod<:Period}
    const dates::Vector{DateTime}
    const values::Vector{T}
    const period::TPeriod
    last_dt::DateTime
end

@inline dates(pv::PeriodicValues) = pv.dates
@inline Base.values(pv::PeriodicValues) = pv.values

function periodic_collector(::Type{T}, period::TPeriod) where {T,TPeriod<:Period}
    dates = Vector{DateTime}()
    values = Vector{T}()
    pv = PeriodicValues(dates, values, period, DateTime(0))

    @inline function collector(dt::DateTime, value::T)
        if (dt - pv.last_dt) >= period
            push!(dates, dt)
            push!(values, value)
            pv.last_dt = dt
        end
        return
    end

    collector, pv
end

@inline function should_collect(pv::PeriodicValues{T,TPeriod}, dt) where {T,TPeriod<:Period}
    (dt - pv.last_dt) >= pv.period
end

# ----------------------------------------------------------

mutable struct PredicateValues{T,TPredicate<:Function}
    const dates::Vector{DateTime}
    const values::Vector{T}
    const predicate::TPredicate
    last_dt::DateTime
    last_value::T
end

@inline dates(pv::PredicateValues) = pv.dates
@inline Base.values(pv::PredicateValues) = pv.values

function predicate_collector(::Type{T}, predicate::TPredicate, init_value::T) where {T,TPredicate<:Function}
    dates = Vector{DateTime}()
    values = Vector{T}()
    pv = PredicateValues(dates, values, predicate, DateTime(0), init_value)

    @inline function collector(dt::DateTime, value::T)
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

@inline function should_collect(pv::PredicateValues{T,TPredicate}, dt) where {T,TPredicate<:Function}
    pv.predicate(pv, dt)
end

# ----------------------------------------------------------

mutable struct MinValue{T}
    dt::DateTime
    min_value::T
end

function min_value_collector(::Type{T}) where {T}
    mv = MinValue{T}(DateTime(0), 1e50)

    @inline function collector(dt::DateTime, value::T)
        if value < mv.min_value
            mv.min_value = value
            mv.dt = dt
        end
        return
    end

    collector, mv
end

# ----------------------------------------------------------

mutable struct MaxValue{T}
    dt::DateTime
    max_value::T
end

function max_value_collector(::Type{T}) where {T}
    mv = MaxValue{T}(DateTime(0), typemin(T))

    @inline function collector(dt::DateTime, value::T)
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

mutable struct DrawdownValues
    const dates::Vector{DateTime}
    const values::Vector{Price}
    const mode::DrawdownMode.T
    max_equity::Price
    last_dt::DateTime
end

@inline dates(pv::DrawdownValues) = pv.dates
@inline Base.values(pv::DrawdownValues) = pv.values

function drawdown_collector(mode::DrawdownMode.T, interval::Dates.Period)
    drawdown_collector(mode, (v, dt, equity) -> dt - v.last_dt >= interval)
end

function drawdown_collector(mode::DrawdownMode.T, predicate::TFunc) where {TFunc<:Function}
    dates = Vector{DateTime}()
    values = Vector{Price}()
    dv = DrawdownValues(
        dates,
        values,
        mode,
        -Inf,
        DateTime(0))

    @inline function collector(dt::DateTime, equity::Price)
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
