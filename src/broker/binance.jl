"""
Simplified Binance fee/financing broker for spot and derivatives.
"""
struct BinanceBroker{TTime<:Dates.AbstractTime} <: AbstractBroker
    maker_spot::Price
    taker_spot::Price
    maker_derivatives::Price
    taker_derivatives::Price
    fee_discount::Price
    borrow_by_cash::Dict{Symbol,StepSchedule{TTime,Price}}
    lend_by_cash::Dict{Symbol,StepSchedule{TTime,Price}}
end

function BinanceBroker(
    ;
    time_type::Type{TTime}=DateTime,
    maker_spot::Real=0.001,
    taker_spot::Real=0.001,
    maker_derivatives::Real=0.0002,
    taker_derivatives::Real=0.0005,
    fee_discount::Real=1.0,
    borrow_by_cash::Dict{Symbol,StepSchedule{TTime,Price}}=Dict{Symbol,StepSchedule{time_type,Price}}(),
    lend_by_cash::Dict{Symbol,StepSchedule{TTime,Price}}=Dict{Symbol,StepSchedule{time_type,Price}}(),
) where {TTime<:Dates.AbstractTime}
    maker_spot_p = Price(maker_spot)
    taker_spot_p = Price(taker_spot)
    maker_deriv_p = Price(maker_derivatives)
    taker_deriv_p = Price(taker_derivatives)
    fee_discount_p = Price(fee_discount)

    maker_spot_p >= 0.0 || throw(ArgumentError("maker_spot must be non-negative."))
    taker_spot_p >= 0.0 || throw(ArgumentError("taker_spot must be non-negative."))
    maker_deriv_p >= 0.0 || throw(ArgumentError("maker_derivatives must be non-negative."))
    taker_deriv_p >= 0.0 || throw(ArgumentError("taker_derivatives must be non-negative."))
    fee_discount_p > 0.0 || throw(ArgumentError("fee_discount must be positive."))

    BinanceBroker{TTime}(
        maker_spot_p,
        taker_spot_p,
        maker_deriv_p,
        taker_deriv_p,
        fee_discount_p,
        borrow_by_cash,
        lend_by_cash,
    )
end

@inline function broker_commission(
    broker::BinanceBroker,
    inst::Instrument,
    ::Dates.AbstractTime,
    ::Quantity,
    ::Price;
    is_maker::Bool=false,
)::CommissionQuote
    rate = if inst.contract_kind == ContractKind.Spot
        is_maker ? broker.maker_spot : broker.taker_spot
    else
        is_maker ? broker.maker_derivatives : broker.taker_derivatives
    end
    CommissionQuote(; fixed=0.0, pct=rate * broker.fee_discount)
end

@inline function broker_interest_rates(
    broker::BinanceBroker{TTime},
    cash_symbol::Symbol,
    dt::Dates.AbstractTime,
    ::Price,
)::Tuple{Price,Price} where {TTime<:Dates.AbstractTime}
    borrow = let sched = get(broker.borrow_by_cash, cash_symbol, nothing)
        sched === nothing ? 0.0 : value_at(sched, dt)
    end
    lend = let sched = get(broker.lend_by_cash, cash_symbol, nothing)
        sched === nothing ? 0.0 : value_at(sched, dt)
    end
    (borrow, lend)
end
