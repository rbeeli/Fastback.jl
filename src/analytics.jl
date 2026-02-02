import DataFrames: DataFrame
import RiskPerf

@inline function _clean_returns(returns::AbstractVector)
    out = Float64[]
    sizehint!(out, length(returns))
    @inbounds for r in returns
        (r === nothing || ismissing(r)) && continue
        v = Float64(r)
        isfinite(v) || continue
        push!(out, v)
    end
    out
end

@inline function _hit_rate(returns::AbstractVector{<:Real})
    wins = 0
    losses = 0
    @inbounds for r in returns
        if r > 0
            wins += 1
        elseif r < 0
            losses += 1
        end
    end
    total = wins + losses
    total == 0 ? NaN : wins / total
end

@inline function _profit_factor(returns::AbstractVector{<:Real})
    gains = 0.0
    losses = 0.0
    @inbounds for r in returns
        if r > 0
            gains += r
        elseif r < 0
            losses += -r
        end
    end
    losses == 0.0 && return gains == 0.0 ? NaN : Inf
    gains / losses
end

"""
    performance_summary_table(returns::AbstractVector; periods_per_year=252, risk_free=0.0, mar=0.0, compound=true)

Return a one-row `DataFrame` with summary performance metrics:
`CAGR`, `vol`, `Sharpe`, `Sortino`, `max DD`, `MAR`, `Calmar`, `hit rate`, and `profit factor`.

`returns` must be simple periodic returns. `risk_free` and `mar` are per-period inputs.
`max_dd` is reported as a positive magnitude. `mar` is the minimum acceptable return used for Sortino.
"""
function performance_summary_table(
    returns::AbstractVector;
    periods_per_year::Real=252,
    risk_free=0.0,
    mar=0.0,
    compound::Bool=true
)
    mar isa Real || throw(ArgumentError("mar must be a scalar for summary table output."))
    r = _clean_returns(returns)
    if isempty(r)
        return DataFrame(;
            cagr=NaN,
            vol=NaN,
            sharpe=NaN,
            sortino=NaN,
            max_dd=NaN,
            mar=mar,
            calmar=NaN,
            hit_rate=NaN,
            profit_factor=NaN,
        )
    end

    cagr = RiskPerf.cagr(r, periods_per_year)
    vol = RiskPerf.volatility(r; multiplier=periods_per_year)
    sharpe = RiskPerf.sharpe_ratio(r; multiplier=periods_per_year, risk_free=risk_free)
    sortino = RiskPerf.sortino_ratio(r; multiplier=periods_per_year, MAR=mar)
    max_dd = RiskPerf.max_drawdown_pct(r; compound=compound)
    calmar = RiskPerf.calmar_ratio(r, periods_per_year; compound=compound)
    hit_rate = _hit_rate(r)
    profit_factor = _profit_factor(r)

    DataFrame(;
        cagr=cagr,
        vol=vol,
        sharpe=sharpe,
        sortino=sortino,
        max_dd=max_dd,
        mar=mar,
        calmar=calmar,
        hit_rate=hit_rate,
        profit_factor=profit_factor,
    )
end

"""
    performance_summary_table(pv::PeriodicValues; periods_per_year=252, risk_free=0.0, mar=0.0, compound=true)

Compute summary metrics from an equity series stored in a `PeriodicValues` collector.
Returns a one-row `DataFrame`.
"""
function performance_summary_table(
    pv::PeriodicValues;
    periods_per_year::Real=252,
    risk_free=0.0,
    mar=0.0,
    compound::Bool=true
)
    eq = values(pv)
    returns = RiskPerf.simple_returns(eq; drop_first=true)
    performance_summary_table(
        returns;
        periods_per_year=periods_per_year,
        risk_free=risk_free,
        mar=mar,
        compound=compound)
end
