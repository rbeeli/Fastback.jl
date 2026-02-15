using Dates

abstract type AbstractBroker end

"""
Commission quote produced by a broker profile.

`fixed` is an additive fee in quote currency.
`pct` is a percentage of traded notional (e.g. `0.001` = 10 bps).
"""
struct CommissionQuote
    fixed::Price
    pct::Price

    function CommissionQuote(; fixed::Real=0.0, pct::Real=0.0)
        fixed_p = Price(fixed)
        pct_p = Price(pct)
        isfinite(fixed_p) || throw(ArgumentError("Commission fixed fee must be finite."))
        isfinite(pct_p) || throw(ArgumentError("Commission pct fee must be finite."))
        fixed_p >= 0.0 || throw(ArgumentError("Commission fixed fee must be non-negative."))
        pct_p >= 0.0 || throw(ArgumentError("Commission pct fee must be non-negative."))
        new(fixed_p, pct_p)
    end
end

"""
Piecewise-constant schedule keyed by time.

`starts[i]` marks the first timestamp where `values[i]` becomes active.
"""
struct StepSchedule{TTime<:Dates.AbstractTime,T}
    starts::Vector{TTime}
    values::Vector{T}

    function StepSchedule(
        starts::Vector{TTime},
        values::Vector{T},
    ) where {TTime<:Dates.AbstractTime,T}
        length(starts) == length(values) || throw(ArgumentError("StepSchedule starts/values length mismatch."))
        new{TTime,T}(starts, values)
    end
end

@inline function StepSchedule(
    entries::AbstractVector{<:Tuple{TTime,T}},
) where {TTime<:Dates.AbstractTime,T}
    n = length(entries)
    starts = Vector{TTime}(undef, n)
    values = Vector{T}(undef, n)
    @inbounds for i in eachindex(entries)
        entry = entries[i]
        starts[i] = entry[1]
        values[i] = entry[2]
    end
    StepSchedule(starts, values)
end

@inline function StepSchedule(
    ;
    starts::Vector{TTime},
    values::Vector{T},
) where {TTime<:Dates.AbstractTime,T}
    StepSchedule(starts, values)
end

@inline _schedule_time(::Type{TTime}, dt::TTime) where {TTime<:Dates.AbstractTime} = dt
@inline _schedule_time(::Type{TTime}, dt::Dates.AbstractTime) where {TTime<:Dates.AbstractTime} = TTime(dt)

"""
Return the active value at `dt`.

For `dt` before the first schedule timestamp, returns the first value.
"""
@inline function value_at(
    schedule::StepSchedule{TTime,T},
    dt::Dates.AbstractTime,
)::T where {TTime<:Dates.AbstractTime,T}
    key = _schedule_time(TTime, dt)
    idx = searchsortedlast(schedule.starts, key)
    idx == 0 && return @inbounds schedule.values[1]
    @inbounds schedule.values[idx]
end
