"""
Flat fee model shared across all instruments.
"""
struct FlatFeeBroker <: AbstractBroker
    commission::CommissionQuote
end

FlatFeeBroker(; fixed::Real=0.0, pct::Real=0.0) = FlatFeeBroker(CommissionQuote(; fixed=fixed, pct=pct))

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
