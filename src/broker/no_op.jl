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
    ::Cash,
    ::TTime,
    ::Price,
)::Tuple{Price,Price} where {TTime<:Dates.AbstractTime}
    (0.0, 0.0)
end

@inline function broker_short_proceeds_rates(
    ::NoOpBroker,
    ::Cash,
    ::TTime,
)::Tuple{Price,Price} where {TTime<:Dates.AbstractTime}
    (1.0, 0.0)
end
