"""
No-op broker.

Commission defaults to zero, financing defaults to zero rates,
and no broker-specific financing schedules are required.
"""
struct NoOpBroker <: AbstractBroker end

@inline function broker_commission(
    ::NoOpBroker,
    ::Instrument,
    ::Dates.AbstractTime,
    ::Quantity,
    ::Price;
    is_maker::Bool=false,
)::CommissionQuote
    CommissionQuote()
end

@inline function broker_interest_rates(
    ::NoOpBroker,
    ::Symbol,
    ::Dates.AbstractTime,
    ::Price,
)::Tuple{Price,Price}
    (0.0, 0.0)
end
