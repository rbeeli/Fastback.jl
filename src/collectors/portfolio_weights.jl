import Base: values
using Dates
import Tables

mutable struct PortfolioWeightsValues{TTime<:Dates.AbstractTime,TPeriod<:Period}
    const dates::Vector{TTime}
    const symbols::Vector{Symbol}
    const weights::Vector{Vector{Price}}
    const period::TPeriod
    const init_value::TTime
    last_dt::TTime
end

@inline dates(pv::PortfolioWeightsValues) = pv.dates
@inline Base.values(pv::PortfolioWeightsValues) = pv.weights

"""
Create a periodic portfolio-weights collector.
Returns a tuple of (collector_function, PortfolioWeightsValues).

Weights are collected as `value_quote(position) / equity(acc, cash)` per instrument.
"""
function portfolio_weights_collector(
    acc::Account{TTime},
    instruments::AbstractVector{<:Instrument{TTime}},
    period::TPeriod;
    cash::Cash=acc.base_currency,
) where {TTime<:Dates.AbstractTime,TPeriod<:Period}
    dts = Vector{TTime}()
    syms = Symbol[getfield(inst, :symbol) for inst in instruments]
    wts = [Price[] for _ in 1:length(instruments)]
    init_value = TTime(0)
    pv = PortfolioWeightsValues{TTime,TPeriod}(
        dts,
        syms,
        wts,
        period,
        init_value,
        init_value,
    )

    @inline function collector(dt::TTime)
        push!(dts, dt)
        equity_value = equity(acc, cash)
        if equity_value == 0.0
            for w in wts
                push!(w, 0.0)
            end
            pv.last_dt = dt
            return
        end

        for (i, inst) in pairs(instruments)
            pos = get_position(acc, inst)
            push!(wts[i], value_quote(pos) / equity_value)
        end
        pv.last_dt = dt
        return
    end

    collector, pv
end

"""
Return `true` when a portfolio-weights collector should emit a new sample.
"""
@inline function should_collect(
    collector::PortfolioWeightsValues{TTime,TPeriod},
    dt::TTime,
) where {TTime<:Dates.AbstractTime,TPeriod<:Period}
    collector.last_dt == collector.init_value || (dt - collector.last_dt) >= collector.period
end

# ----- Tables.jl ------

Tables.istable(::Type{PortfolioWeightsValues{TTime,TPeriod}}) where {TTime<:Dates.AbstractTime,TPeriod} = true
Tables.rowaccess(::Type{PortfolioWeightsValues{TTime,TPeriod}}) where {TTime<:Dates.AbstractTime,TPeriod} = true

function Tables.schema(pv::PortfolioWeightsValues{TTime,TPeriod}) where {TTime<:Dates.AbstractTime,TPeriod}
    names = Tuple(vcat([:date], pv.symbols))
    types = Tuple(vcat([TTime], fill(Price, length(pv.symbols))))
    Tables.Schema(names, types)
end

struct PortfolioWeightsRows{TTime<:Dates.AbstractTime,TPeriod}
    pv::PortfolioWeightsValues{TTime,TPeriod}
end

Tables.rows(pv::PortfolioWeightsValues{TTime,TPeriod}) where {TTime<:Dates.AbstractTime,TPeriod} = PortfolioWeightsRows{TTime,TPeriod}(pv)

Base.length(iter::PortfolioWeightsRows{TTime,TPeriod}) where {TTime<:Dates.AbstractTime,TPeriod} = length(iter.pv.dates)

function Base.iterate(iter::PortfolioWeightsRows{TTime,TPeriod}, idx::Int=1) where {TTime<:Dates.AbstractTime,TPeriod}
    idx > length(iter.pv.dates) && return nothing
    pv = iter.pv
    date_ = @inbounds pv.dates[idx]
    vals = ntuple(i -> (@inbounds pv.weights[i][idx]), length(pv.symbols))
    names = Tuple(vcat([:date], pv.symbols))
    row = NamedTuple{names}((date_, vals...))
    return row, idx + 1
end
