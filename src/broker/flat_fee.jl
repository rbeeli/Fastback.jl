"""
Flat signed-commission model with optional per-cash financing rates.

`fixed` and `pct` may be positive (fee) or negative (rebate).
"""
struct FlatFeeBroker <: AbstractBroker
    commission::CommissionQuote
    borrow_by_cash::Dict{Symbol,Price}
    lend_by_cash::Dict{Symbol,Price}
    short_proceeds_exclusion_by_cash::Dict{Symbol,Price}
    short_proceeds_rebate_by_cash::Dict{Symbol,Price}
end

function FlatFeeBroker(
    ;
    fixed::Real=0.0,
    pct::Real=0.0,
    borrow_by_cash::Dict{Symbol,Price}=Dict{Symbol,Price}(),
    lend_by_cash::Dict{Symbol,Price}=Dict{Symbol,Price}(),
    short_proceeds_exclusion_by_cash::Dict{Symbol,Price}=Dict{Symbol,Price}(),
    short_proceeds_rebate_by_cash::Dict{Symbol,Price}=Dict{Symbol,Price}(),
)
    @inbounds for (cash, frac) in short_proceeds_exclusion_by_cash
        isfinite(frac) || throw(ArgumentError("short_proceeds_exclusion_by_cash[$(cash)] must be finite."))
        0.0 <= frac <= 1.0 || throw(ArgumentError("short_proceeds_exclusion_by_cash[$(cash)] must be in [0, 1]."))
    end
    @inbounds for (cash, rate) in short_proceeds_rebate_by_cash
        isfinite(rate) || throw(ArgumentError("short_proceeds_rebate_by_cash[$(cash)] must be finite."))
    end

    FlatFeeBroker(
        CommissionQuote(; fixed=fixed, pct=pct),
        borrow_by_cash,
        lend_by_cash,
        short_proceeds_exclusion_by_cash,
        short_proceeds_rebate_by_cash,
    )
end

@inline function broker_commission(
    broker::FlatFeeBroker,
    ::Instrument,
    ::Dates.AbstractTime,
    ::Quantity,
    ::Price;
    is_maker::Bool=false,
)::CommissionQuote
    broker.commission
end

@inline function broker_interest_rates(
    broker::FlatFeeBroker,
    cash::Cash,
    ::TTime,
    ::Price,
)::Tuple{Price,Price} where {TTime<:Dates.AbstractTime}
    (
        get(broker.borrow_by_cash, cash.symbol, 0.0),
        get(broker.lend_by_cash, cash.symbol, 0.0),
    )
end

@inline function broker_short_proceeds_rates(
    broker::FlatFeeBroker,
    cash::Cash,
    ::TTime,
)::Tuple{Price,Price} where {TTime<:Dates.AbstractTime}
    (
        get(broker.short_proceeds_exclusion_by_cash, cash.symbol, 1.0),
        get(broker.short_proceeds_rebate_by_cash, cash.symbol, 0.0),
    )
end
