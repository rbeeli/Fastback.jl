"""
Simplified IBKR Pro Fixed style broker.

US option commissions include the configured premium-tier commission plus
predictable per-contract/pass-through regulatory, clearing, and transaction
fees. Exchange-specific maker/taker routing fees are intentionally left to
custom broker overrides or calibrated flat-fee overlays.
"""
struct IBKRProFixedBroker{TTime<:Dates.AbstractTime} <: AbstractBroker
    equity_per_share::Price
    equity_min::Price
    equity_max_pct::Price
    option_per_contract::Price
    option_min::Price
    option_low_premium_per_contract::Price
    option_mid_premium_per_contract::Price
    option_low_premium_threshold::Price
    option_mid_premium_threshold::Price
    option_orf_per_contract::Price
    option_occ_per_contract::Price
    option_cat_per_contract::Price
    option_finra_taf_per_contract_sold::Price
    option_sec_transaction_rate::Price
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
    option_per_contract::Real=0.65,
    option_min::Real=1.0,
    option_low_premium_per_contract::Real=0.25,
    option_mid_premium_per_contract::Real=0.50,
    option_low_premium_threshold::Real=0.05,
    option_mid_premium_threshold::Real=0.10,
    option_orf_per_contract::Real=0.02295,
    option_occ_per_contract::Real=0.025,
    option_cat_per_contract::Real=0.0003,
    option_finra_taf_per_contract_sold::Real=0.00329,
    option_sec_transaction_rate::Real=0.0000206,
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
    option_per_contract_p = Price(option_per_contract)
    option_min_p = Price(option_min)
    option_low_p = Price(option_low_premium_per_contract)
    option_mid_p = Price(option_mid_premium_per_contract)
    option_low_threshold_p = Price(option_low_premium_threshold)
    option_mid_threshold_p = Price(option_mid_premium_threshold)
    option_orf_p = Price(option_orf_per_contract)
    option_occ_p = Price(option_occ_per_contract)
    option_cat_p = Price(option_cat_per_contract)
    option_finra_taf_p = Price(option_finra_taf_per_contract_sold)
    option_sec_rate_p = Price(option_sec_transaction_rate)
    borrow_spread_p = Price(borrow_spread)
    lend_spread_p = Price(lend_spread)
    credit_floor_p = Price(credit_no_interest_balance)
    short_exclusion_p = Price(short_proceeds_exclusion)
    short_rebate_spread_p = Price(short_proceeds_rebate_spread)
    equity_per_share_p >= 0.0 || throw(ArgumentError("equity_per_share must be non-negative."))
    equity_min_p >= 0.0 || throw(ArgumentError("equity_min must be non-negative."))
    equity_max_pct_p >= 0.0 || throw(ArgumentError("equity_max_pct must be non-negative."))
    option_per_contract_p >= 0.0 || throw(ArgumentError("option_per_contract must be non-negative."))
    option_min_p >= 0.0 || throw(ArgumentError("option_min must be non-negative."))
    option_low_p >= 0.0 || throw(ArgumentError("option_low_premium_per_contract must be non-negative."))
    option_mid_p >= 0.0 || throw(ArgumentError("option_mid_premium_per_contract must be non-negative."))
    option_low_threshold_p >= 0.0 || throw(ArgumentError("option_low_premium_threshold must be non-negative."))
    option_mid_threshold_p >= option_low_threshold_p || throw(ArgumentError("option_mid_premium_threshold must be >= option_low_premium_threshold."))
    option_orf_p >= 0.0 || throw(ArgumentError("option_orf_per_contract must be non-negative."))
    option_occ_p >= 0.0 || throw(ArgumentError("option_occ_per_contract must be non-negative."))
    option_cat_p >= 0.0 || throw(ArgumentError("option_cat_per_contract must be non-negative."))
    option_finra_taf_p >= 0.0 || throw(ArgumentError("option_finra_taf_per_contract_sold must be non-negative."))
    option_sec_rate_p >= 0.0 || throw(ArgumentError("option_sec_transaction_rate must be non-negative."))
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
        option_per_contract_p,
        option_min_p,
        option_low_p,
        option_mid_p,
        option_low_threshold_p,
        option_mid_threshold_p,
        option_orf_p,
        option_occ_p,
        option_cat_p,
        option_finra_taf_p,
        option_sec_rate_p,
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

    if inst.spec.contract_kind == ContractKind.Spot
        notional = qty_abs * abs(price) * inst.spec.multiplier
        fee = min(
            max(broker.equity_min, broker.equity_per_share * qty_abs),
            broker.equity_max_pct * notional,
        )
        return CommissionQuote(; fixed=fee, pct=0.0)
    elseif inst.spec.contract_kind == ContractKind.Option
        per_contract = if abs(price) < broker.option_low_premium_threshold
            broker.option_low_premium_per_contract
        elseif abs(price) < broker.option_mid_premium_threshold
            broker.option_mid_premium_per_contract
        else
            broker.option_per_contract
        end
        base_fee = max(broker.option_min, qty_abs * per_contract)
        pass_through_fee = qty_abs * (
            broker.option_orf_per_contract +
            broker.option_occ_per_contract +
            broker.option_cat_per_contract
        )
        if qty < 0.0
            premium_sale_value = qty_abs * abs(price) * inst.spec.multiplier
            pass_through_fee += qty_abs * broker.option_finra_taf_per_contract_sold
            pass_through_fee += premium_sale_value * broker.option_sec_transaction_rate
        end
        return CommissionQuote(; fixed=base_fee + pass_through_fee, pct=0.0)
    end

    per_contract = get(broker.futures_per_contract, inst.spec.symbol, 0.0)
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
