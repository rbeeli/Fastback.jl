using Dates

abstract type AbstractBroker end

"""
Commission quote produced by a broker.

`fixed` is an additive amount in quote currency (positive = fee, negative = rebate).
`pct` is a percentage of traded notional (e.g. `0.001` = 10 bps fee, `-0.001` = 10 bps rebate).
"""
struct CommissionQuote
    fixed::Price
    pct::Price

    function CommissionQuote(; fixed::Real=0.0, pct::Real=0.0)
        fixed_p = Price(fixed)
        pct_p = Price(pct)
        isfinite(fixed_p) || throw(ArgumentError("Commission fixed fee must be finite."))
        isfinite(pct_p) || throw(ArgumentError("Commission pct fee must be finite."))
        new(fixed_p, pct_p)
    end
end

"""
Fill per-leg commission quotes for a listed-option package order.

The default implementation preserves historical behavior by pricing each leg
as an independent order. Broker profiles may override this for combo orders
whose commission schedule applies order-level minimums to the package.
"""
function _broker_option_strategy_commissions_per_leg!(
    dest::Vector{CommissionQuote},
    broker::AbstractBroker,
    orders::Vector{Order{TTime}},
    dt::TTime,
    fill_qtys::Union{Nothing,Vector{Quantity}},
    fill_prices::Vector{Price},
    is_makers::Union{Nothing,Vector{Bool}},
)::Vector{CommissionQuote} where {TTime<:Dates.AbstractTime}
    n = length(orders)
    length(dest) == n || resize!(dest, n)
    @inbounds for i in 1:n
        order = orders[i]
        fill_qty = if fill_qtys === nothing
            order.quantity
        else
            qty = fill_qtys[i]
            qty != 0.0 ? qty : order.quantity
        end
        is_maker = is_makers !== nothing && is_makers[i]
        dest[i] = broker_commission(
            broker,
            order.inst,
            dt,
            fill_qty,
            fill_prices[i];
            is_maker=is_maker,
        )
    end
    dest
end

function broker_option_strategy_commissions!(
    dest::Vector{CommissionQuote},
    broker::AbstractBroker,
    orders::Vector{Order{TTime}},
    dt::TTime,
    fill_qtys::Union{Nothing,Vector{Quantity}},
    fill_prices::Vector{Price},
    is_makers::Union{Nothing,Vector{Bool}},
)::Vector{CommissionQuote} where {TTime<:Dates.AbstractTime}
    _broker_option_strategy_commissions_per_leg!(
        dest,
        broker,
        orders,
        dt,
        fill_qtys,
        fill_prices,
        is_makers,
    )
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

"""
Return the active value at `dt`.

For `dt` before the first schedule timestamp, returns the first value.
"""
@inline function value_at(
    schedule::StepSchedule{TTime,T},
    dt::TTime,
)::T where {TTime<:Dates.AbstractTime,T}
    idx = searchsortedlast(schedule.starts, dt)
    idx == 0 && return @inbounds schedule.values[1]
    @inbounds schedule.values[idx]
end
