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
include("account.jl")
include("execution.jl")
include("logic.jl")
include("collectors.jl")
include("tables.jl")
include("print.jl")
include("backtest_runner.jl")

# Core types
export Fastback,
    Price,
    Quantity,
    TradeDir,
    SettlementStyle,
    MarginMode,
    ContractKind,
    AccountMode,
    OrderRejectReason,
    Cash,
    Instrument,
    Order,
    Trade,
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
    FillImpact,
    compute_fill_impact,
    fill_order!,
    is_realizing,
    realized_return

# Account operations
export cash_asset,
    has_cash_asset,
    register_cash_asset!,
    cash_balance,
    equity,
    init_margin_used,
    maint_margin_used,
    available_funds,
    excess_liquidity,
    deposit!,
    withdraw!,
    register_instrument!,
    get_position,
    is_exposed_to,
    oid!,
    tid!,
    format_datetime

# Position analytics
export has_exposure,
    calc_pnl_local,
    calc_return_local,
    margin_init_local,
    margin_maint_local,
    calc_realized_qty,
    calc_exposure_increase_quantity

# Exchange rate utilities
export add_asset!,
    get_rate,
    get_rates_matrix,
    update_rate!

# Portfolio logic
export update_pnl!,
    update_valuation!,
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

# Backtesting
export batch_backtest

# Tables integration
export balances_table,
    equities_table,
    positions_table,
    trades_table

# Formatting helpers
export format_cash,
    format_base,
    format_quote,
    format_period_HHMMSS,
    has_expiry,
    is_expired,
    is_active,
    ensure_active

# Printing helpers
export print_cash_balances,
    print_equity_balances,
    print_positions,
    print_trades

# Utilities
export params_combinations,
    compute_eta

end # module
