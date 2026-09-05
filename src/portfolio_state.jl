"""Explicit transition from one concrete futures/perpetual contract to another."""
struct RollTransition
    from_index::Int
    to_index::Int

    function RollTransition(from_index::Integer, to_index::Integer)
        from = Int(from_index)
        to = Int(to_index)
        from > 0 && to > 0 || throw(ArgumentError("Roll instrument indices must be positive."))
        from != to || throw(ArgumentError("Roll source and destination must be distinct."))
        new(from, to)
    end
end

RollTransition(from::Instrument, to::Instrument) = RollTransition(from.index, to.index)

"""Complete simulated execution observation returned by a portfolio fill model."""
struct ModelFill
    price::Price
    bid::Price
    ask::Price
    last::Price
    is_maker::Bool

    function ModelFill(
        price::Real,
        bid::Real,
        ask::Real,
        last::Real
        ;
        is_maker::Bool=false,
    )
        price_value = Price(price)
        bid_value = Price(bid)
        ask_value = Price(ask)
        last_value = Price(last)
        all(isfinite, (price_value, bid_value, ask_value, last_value)) ||
            throw(ArgumentError("Model fill prices must be finite."))
        bid_value <= ask_value || throw(ArgumentError("Model fill bid cannot exceed ask."))
        new(price_value, bid_value, ask_value, last_value, is_maker)
    end
end

struct _RebalanceLeg{TTime<:Dates.AbstractTime}
    inst::Instrument{TTime}
    quantity::Quantity
    reduction::Bool
    fill::Union{Nothing,ModelFill}
end

struct _PlannedRoll{TTime<:Dates.AbstractTime}
    from_inst::Instrument{TTime}
    to_inst::Instrument{TTime}
    close_fill::ModelFill
    open_fill::ModelFill
end

# Reused by all Portfolio wrappers for an account; results never alias these buffers.
struct _RebalanceScratch{TTime<:Dates.AbstractTime}
    current::Vector{Quantity}
    desired::Vector{Quantity}
    target_member::Vector{Bool}
    indices::Vector{Int}
    roll_sources::Set{Int}
    pending_rolls::Vector{RollTransition}
    ordered_rolls::Vector{RollTransition}
    planned_rolls::Vector{_PlannedRoll{TTime}}
    legs::Vector{_RebalanceLeg{TTime}}
    available::Vector{Price}
    remaining::Vector{Price}
end

_RebalanceScratch{TTime}() where {TTime<:Dates.AbstractTime} = _RebalanceScratch{TTime}(
    Quantity[], Quantity[], Bool[], Int[], Set{Int}(), RollTransition[],
    RollTransition[], _PlannedRoll{TTime}[], _RebalanceLeg{TTime}[], Price[], Price[],
)
