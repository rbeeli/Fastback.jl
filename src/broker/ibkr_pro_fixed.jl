"""
Simplified IBKR Pro Fixed style broker.
"""
struct IBKRProFixedBroker{TTime<:Dates.AbstractTime} <: AbstractBroker
    equity_per_share::Price
    equity_min::Price
    equity_max_pct::Price
    futures_per_contract::Dict{Symbol,Price}
    benchmark_by_cash::Dict{Symbol,StepSchedule{TTime,Price}}
    borrow_spread::Price
    lend_spread::Price
    credit_no_interest_balance::Price
    short_proceeds_exclusion::Price
    short_proceeds_rebate_spread::Price
end

function IBKRProFixedBroker(
    ;
    time_type::Type{TTime}=DateTime,
    equity_per_share::Real=0.005,
    equity_min::Real=1.0,
    equity_max_pct::Real=0.01,
    futures_per_contract::Dict{Symbol,Price}=Dict{Symbol,Price}(),
    benchmark_by_cash::Dict{Symbol,StepSchedule{TTime,Price}}=Dict{Symbol,StepSchedule{time_type,Price}}(),
    borrow_spread::Real=0.015,
    lend_spread::Real=0.005,
    credit_no_interest_balance::Real=10_000.0,
    short_proceeds_exclusion::Real=1.0,
    short_proceeds_rebate_spread::Real=lend_spread,
) where {TTime<:Dates.AbstractTime}
    equity_per_share_p = Price(equity_per_share)
    equity_min_p = Price(equity_min)
    equity_max_pct_p = Price(equity_max_pct)
    borrow_spread_p = Price(borrow_spread)
    lend_spread_p = Price(lend_spread)
    credit_floor_p = Price(credit_no_interest_balance)
    short_exclusion_p = Price(short_proceeds_exclusion)
    short_rebate_spread_p = Price(short_proceeds_rebate_spread)
    equity_per_share_p >= 0.0 || throw(ArgumentError("equity_per_share must be non-negative."))
    equity_min_p >= 0.0 || throw(ArgumentError("equity_min must be non-negative."))
    equity_max_pct_p >= 0.0 || throw(ArgumentError("equity_max_pct must be non-negative."))
    borrow_spread_p >= 0.0 || throw(ArgumentError("borrow_spread must be non-negative."))
    lend_spread_p >= 0.0 || throw(ArgumentError("lend_spread must be non-negative."))
    credit_floor_p >= 0.0 || throw(ArgumentError("credit_no_interest_balance must be non-negative."))
    isfinite(short_exclusion_p) || throw(ArgumentError("short_proceeds_exclusion must be finite."))
    0.0 <= short_exclusion_p <= 1.0 || throw(ArgumentError("short_proceeds_exclusion must be in [0, 1]."))
    short_rebate_spread_p >= 0.0 || throw(ArgumentError("short_proceeds_rebate_spread must be non-negative."))

    IBKRProFixedBroker{TTime}(
        equity_per_share_p,
        equity_min_p,
        equity_max_pct_p,
        futures_per_contract,
        benchmark_by_cash,
        borrow_spread_p,
        lend_spread_p,
        credit_floor_p,
        short_exclusion_p,
        short_rebate_spread_p,
    )
end

@inline function broker_commission(
    broker::IBKRProFixedBroker,
    inst::Instrument,
    ::Dates.AbstractTime,
    qty::Quantity,
    price::Price;
    is_maker::Bool=false,
)::CommissionQuote
    qty_abs = abs(qty)
    qty_abs == 0.0 && return CommissionQuote()

    if inst.contract_kind == ContractKind.Spot
        notional = qty_abs * abs(price) * inst.multiplier
        fee = min(
            max(broker.equity_min, broker.equity_per_share * qty_abs),
            broker.equity_max_pct * notional,
        )
        return CommissionQuote(; fixed=fee, pct=0.0)
    end

    per_contract = get(broker.futures_per_contract, inst.symbol, 0.0)
    CommissionQuote(; fixed=qty_abs * per_contract, pct=0.0)
end

@inline function broker_interest_rates(
    broker::IBKRProFixedBroker{TTime},
    cash::Cash,
    dt::TTime,
    balance::Price,
)::Tuple{Price,Price} where {TTime<:Dates.AbstractTime}
    benchmark_schedule = get(broker.benchmark_by_cash, cash.symbol, nothing)
    benchmark_schedule === nothing && return (0.0, 0.0)

    benchmark = value_at(benchmark_schedule, dt)
    borrow = max(0.0, benchmark + broker.borrow_spread)
    raw_lend = max(0.0, benchmark - broker.lend_spread)
    lend = if balance > broker.credit_no_interest_balance
        raw_lend * (balance - broker.credit_no_interest_balance) / balance
    else
        0.0
    end

    (borrow, lend)
end

@inline function broker_short_proceeds_rates(
    broker::IBKRProFixedBroker{TTime},
    cash::Cash,
    dt::TTime,
)::Tuple{Price,Price} where {TTime<:Dates.AbstractTime}
    benchmark_schedule = get(broker.benchmark_by_cash, cash.symbol, nothing)
    benchmark_schedule === nothing && return (broker.short_proceeds_exclusion, 0.0)

    benchmark = value_at(benchmark_schedule, dt)
    rebate = max(0.0, benchmark - broker.short_proceeds_rebate_spread)
    (broker.short_proceeds_exclusion, rebate)
end
