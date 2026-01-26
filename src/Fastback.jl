module Fastback

const Price = Float64           # quote bid/ask, traded price
const Quantity = Float64        # trade volume / number of shares

include("utils.jl")
include("enums.jl")
include("cash.jl")
include("instrument.jl")
include("order.jl")
include("trade.jl")
include("position.jl")
include("exchange_rates.jl")
include("cashflows.jl")
include("account.jl")
include("contract_math.jl")
include("interest.jl")
include("borrow_fees.jl")
include("funding.jl")
include("execution.jl")
include("risk.jl")
include("margin.jl")
include("logic.jl")
include("collectors.jl")
include("tables.jl")
include("print.jl")
include("backtest_runner.jl")
include("liquidation.jl")
include("events.jl")

# Core types
export Fastback,
    Price,
    Quantity,
    TradeDir,
    SettlementStyle,
    DeliveryStyle,
    MarginMode,
    MarginingStyle,
    ContractKind,
    PhysicalExpiryPolicy,
    AccountMode,
    CashflowKind,
    OrderRejectReason,
    TradeReason,
    Cash,
    Instrument,
    Order,
    Trade,
    Cashflow,
    Position,
    Account,
    ExchangeRates,
    OneExchangeRates,
    SpotExchangeRates

# Trade direction helpers
export trade_dir,
    is_long,
    is_short,
    opposite_dir

# Order and trade utilities
export symbol,
    nominal_value,
    FillPlan,
    plan_fill,
    fill_order!,
    is_realizing,
    realized_return,
    cfid!

# Account operations
export cash_asset,
    has_cash_asset,
    has_base_ccy,
    register_cash_asset!,
    cash_base_ccy,
    quote_cash,
    settle_cash,
    quote_idx,
    settle_idx,
    get_rate_base_ccy,
    to_settle,
    to_quote,
    to_base,
    cash_balance,
    equity,
    equity_base_ccy,
    balance_base_ccy,
    init_margin_used,
    init_margin_used_base_ccy,
    maint_margin_used,
    maint_margin_used_base_ccy,
    available_funds,
    available_funds_base_ccy,
    excess_liquidity,
    excess_liquidity_base_ccy,
    maint_deficit_base_ccy,
    init_deficit_base_ccy,
    is_under_maintenance,
    deposit!,
    withdraw!,
    set_interest_rates!,
    accrue_interest!,
    accrue_borrow_fees!,
    apply_funding!,
    register_instrument!,
    get_position,
    is_exposed_to,
    oid!,
    tid!,
    format_datetime,
    exchange_rates,
    liquidate_all!,
    liquidate_to_maintenance!

# Position analytics
export has_exposure,
    value_quote,
    pnl_quote,
    cash_delta_quote,
    calc_pnl_quote,
    calc_return_quote,
    margin_init_quote,
    margin_maint_quote,
    margin_init_settle,
    margin_maint_settle,
    calc_realized_qty,
    calc_exposure_increase_quantity

# Exchange rate utilities
export add_asset!,
    get_rate,
    get_rates_matrix,
    update_rate!

# Portfolio logic
export update_valuation!,
    update_margin!,
    update_marks!,
    settle_expiry!

# Collectors
export PeriodicValues,
    PredicateValues,
    DrawdownValues,
    DrawdownMode,
    dates,
    periodic_collector,
    predicate_collector,
    drawdown_collector,
    should_collect,
    MinValue,
    MaxValue,
    min_value_collector,
    max_value_collector

# Event driver
export MarkUpdate,
    FundingUpdate,
    FXUpdate,
    advance_time!,
    process_step!,
    process_expiries!

# Backtesting
export batch_backtest

# Tables integration
export balances_table,
    equities_table,
    positions_table,
    trades_table,
    cashflows_table

# Formatting helpers
export format_cash,
    format_base,
    format_quote,
    format_period_HHMMSS,
    has_expiry,
    is_expired,
    is_active,
    ensure_active,
    is_margined_spot

# Printing helpers
export print_cash_balances,
    print_equity_balances,
    print_positions,
    print_trades,
    print_cashflows

# Utilities
export params_combinations,
    compute_eta

end # module
