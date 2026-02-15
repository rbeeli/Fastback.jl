module Fastback

const Price = Float64           # quote bid/ask, traded price
const Quantity = Float64        # trade volume / number of shares

include("utils.jl")
include("enums.jl")
include("errors.jl")
include("cash.jl")
include("instrument.jl")
include("order.jl")
include("trade.jl")
include("position.jl")
include("exchange_rates.jl")
include("cashflows.jl")
include("broker/base.jl")
include("broker/no_op.jl")
include("broker/flat_fee.jl")
include("broker/ibkr_pro_fixed.jl")
include("broker/binance.jl")
include("account.jl")
include("contract_math.jl")
include("interest.jl")
include("borrow_fees.jl")
include("funding.jl")
include("execution.jl")
include("risk.jl")
include("margin.jl")
include("logic.jl")
include("invariants.jl")
include("collectors.jl")
include("tables.jl")
include("analytics.jl")
include("print.jl")
include("plots.jl")
include("backtest_runner.jl")
include("liquidation.jl")
include("events.jl")

# Core types
export Price,
    Quantity,
    TradeDir,
    SettlementStyle,
    MarginRequirement,
    MarginAggregation,
    ContractKind,
    AccountFunding,
    CashflowKind,
    OrderRejectReason,
    OrderRejectError,
    TradeReason,
    AbstractBroker,
    NoOpBroker,
    FlatFeeBroker,
    IBKRProFixedBroker,
    BinanceBroker,
    StepSchedule,
    value_at,
    CommissionQuote,
    Cash,
    CashSpec,
    Instrument,
    Order,
    Trade,
    Cashflow,
    Position,
    Account,
    ExchangeRates

# Trade direction helpers
export trade_dir,
    is_long,
    is_short,
    opposite_dir

# Broker hooks
export broker_commission,
    broker_interest_rates

# Order and trade utilities
export symbol,
    nominal_value,
    fill_order!,
    roll_position!,
    is_realizing,
    realized_return

# Cash ledger operations
export cash_asset,
    cash_index,
    has_cash_asset,
    register_cash_asset!

# Account operations
export quote_cash,
    settle_cash,
    margin_cash,
    get_rate_base_ccy,
    to_settle,
    to_quote,
    to_margin,
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
    accrue_interest!,
    accrue_borrow_fees!,
    apply_funding!,
    register_instrument!,
    get_position,
    is_exposed_to,
    oid!,
    format_datetime,
    liquidate_all!,
    liquidate_to_maintenance!

# Position analytics
export has_exposure,
    value_quote,
    pnl_quote

# Contract math
export calc_value_quote,
    calc_pnl_quote,
    margin_init_margin_ccy,
    margin_maint_margin_ccy

# Exchange rate utilities
export get_rate,
    get_rates_matrix,
    update_rate!

# Portfolio logic
export update_marks!,
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

# Analytics
export performance_summary_table

# Formatting helpers
export format_cash,
    format_base,
    format_quote,
    has_expiry,
    is_expired,
    is_active,
    ensure_active,
    is_margined_spot,
    spot_instrument,
    perpetual_instrument,
    future_instrument

# Printing helpers
export print_cash_balances,
    print_equity_balances,
    print_positions,
    print_trades,
    print_cashflows

# Plots extension (requires Plots.jl; violins need StatsPlots)
export plot_title,
    plot_balance,
    plot_balance!,
    plot_equity,
    plot_equity!,
    plot_equity_seq,
    plot_open_orders,
    plot_open_orders!,
    plot_open_orders_seq,
    plot_drawdown,
    plot_drawdown!,
    plot_drawdown_seq,
    plot_equity_drawdown,
    plot_equity_drawdown!,
    plot_exposure,
    plot_exposure!,
    plot_cashflows,
    plot_violin_realized_returns_by_day,
    plot_violin_realized_returns_by_hour,
    plot_realized_cum_returns_by_hour,
    plot_realized_cum_returns_by_hour_seq_net,
    plot_realized_cum_returns_by_hour_seq_gross,
    plot_realized_cum_returns_by_hour_seq,
    plot_realized_cum_returns_by_weekday,
    plot_realized_cum_returns_by_weekday_seq

# Utilities
export params_combinations

end # module
