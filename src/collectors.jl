
mutable struct PeriodicValues{T}
    values          ::Vector{Tuple{DateTime, T}}
    period          ::Period
    last_dt         ::DateTime
end

function periodic_collector(
    type        ::Type{T},
    period      ::Period
)::Tuple{Function, PeriodicValues{T}} where T
    values = Vector{Tuple{DateTime, T}}()
    pv = PeriodicValues{T}(values, period, DateTime(0))

    @inline function collector(dt::DateTime, value::T)
        if (dt - pv.last_dt) >= period
            push!(values, (dt, value))
            pv.last_dt = dt
        end
        return
    end

    return collector, pv
end

@inline should_collect(pv::PeriodicValues, dt) = (dt - pv.last_dt) >= pv.period

# ----------------------------------------------------------

mutable struct PredicateValues{T}
    values          ::Vector{Tuple{DateTime, T}}
    last_dt         ::DateTime
    last_value      ::T
end

function predicate_collector(
    type            ::Type{T},
    predicate       ::TFunc,
    init_value      ::T
) where {T, TFunc <: Function}
    values = Vector{Tuple{DateTime, T}}()
    pv = PredicateValues{T}(values, DateTime(0), init_value)

    @inline function collector(dt::DateTime, collect_func::TCollectFunc) where {TCollectFunc}
        if predicate(pv, dt)
            value = collect_func(pv, dt)
            push!(values, (dt, value))
            pv.last_dt = dt
            pv.last_value = value
        end
        return
    end

    return collector, pv
end

# ----------------------------------------------------------

mutable struct MinValue{T}
    dt         ::DateTime
    min_value  ::T
end

function min_value_collector(type::Type{T}) where T
    mv = MinValue{T}(DateTime(0), 1e50)

    @inline function collector(dt::DateTime, value::T)
        if value < mv.min_value
            mv.min_value = value
            mv.dt = dt
        end
        return
    end

    return collector, mv
end

# ----------------------------------------------------------

mutable struct MaxValue{T}
    dt         ::DateTime
    max_value  ::T
end

function max_value_collector(type::Type{T}) where T
    mv = MaxValue{T}(DateTime(0), typemin(T))

    @inline function collector(dt::DateTime, value::T)
        if value > mv.max_value
            mv.max_value = value
            mv.dt = dt
        end
        return
    end

    return collector, mv
end

# ----------------------------------------------------------

@enum DrawdownMode Percentage PnL

mutable struct DrawdownValues
    values          ::Vector{Tuple{DateTime, Price}}
    mode            ::DrawdownMode
    max_equity      ::Price
    last_dt         ::DateTime
end

function drawdown_collector(mode::DrawdownMode, predicate::TFunc) where {TFunc <: Function}
    dv = DrawdownValues(
        Vector{Tuple{DateTime, Price}}(),
        mode,
        -1e50,
        DateTime(0))

    @inline function collector(dt::DateTime, equity::Price)
        # keep track of max equity value
        dv.max_equity = max(dv.max_equity, equity)

        # should collect new drawdown value?
        if predicate(dv, dt, equity)
            drawdown = min(0.0, equity - dv.max_equity)
            if mode == Percentage::DrawdownMode
                drawdown /= dv.max_equity
            end
            push!(dv.values, (dt, drawdown))
            dv.last_dt = dt
        end

        return
    end

    return collector, dv
end

# ----------------------------------------------------------
