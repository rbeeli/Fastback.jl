"""
Flat fee commission model with optional per-cash financing rates.
"""
struct FlatFeeBroker <: AbstractBroker
    commission::CommissionQuote
    borrow_by_cash::Dict{Symbol,Price}
    lend_by_cash::Dict{Symbol,Price}
end

function FlatFeeBroker(
    ;
    fixed::Real=0.0,
    pct::Real=0.0,
    borrow_by_cash::Dict{Symbol,Price}=Dict{Symbol,Price}(),
    lend_by_cash::Dict{Symbol,Price}=Dict{Symbol,Price}(),
)
    FlatFeeBroker(
        CommissionQuote(; fixed=fixed, pct=pct),
        borrow_by_cash,
        lend_by_cash,
    )
end

@inline function broker_commission(
    profile::FlatFeeBroker,
    ::Instrument,
    ::Dates.AbstractTime,
    ::Quantity,
    ::Price;
    is_maker::Bool=false,
)::CommissionQuote
    profile.commission
end

@inline function broker_interest_rates(
    profile::FlatFeeBroker,
    cash_symbol::Symbol,
    ::Dates.AbstractTime,
    ::Price,
)::Tuple{Price,Price}
    (
        get(profile.borrow_by_cash, cash_symbol, 0.0),
        get(profile.lend_by_cash, cash_symbol, 0.0),
    )
end
