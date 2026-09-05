# API index

Exhaustive public API list (core, built-in SVG plotting, and optional Plots extension).
For narrative guidance, see [How-to](how_to.md) and [Glossary](glossary.md).
For details, open the REPL and type `?symbol` to view docstrings.

## Core types and enums

- `Price`, `Quantity`
- `TradeDir`, `SettlementStyle`, `MarginRequirement`, `MarginAggregation`, `ContractKind`, `OptionRight`, `OptionExerciseStyle`, `OptionStrategyCommissionMode`, `AccountFunding`, `CashflowKind`, `OrderRejectReason`, `OrderRejectError`, `AccountPoisonedError`, `TradeReason`, `OrphanPositionPolicy`
- `Cash`, `CashSpec`, `InstrumentSpec`, `Instrument`, `Order`, `Trade`, `Cashflow`, `Position`, `Account`
- `ExchangeRates`

## Trade direction helpers

- `trade_dir`, `is_long`, `is_short`, `opposite_dir`

## Broker hooks

- `broker_commission`, `broker_option_strategy_commissions!`, `broker_interest_rates`, `broker_short_proceeds_rates`

## Order and trade utilities

- `symbol`, `notional_value`, `fill_order!`, `fill_option_strategy!`, `roll_position!`, `apply_spot_corporate_action!`
- `realized_notional_quote`, `is_realizing`, `realized_return_gross`, `realized_return_net`

## Cash ledger operations

- `cash_asset`, `cash_index`, `has_cash_asset`, `register_cash_asset!`

## Account operations

- `quote_cash`, `settle_cash`, `margin_cash`
- `get_rate_base_ccy`, `to_settle`, `to_quote`, `to_margin`, `to_base`
- `cash_balance`, `equity`, `equity_base_ccy`, `balance_base_ccy`
- `init_margin_used`, `init_margin_used_base_ccy`, `maint_margin_used`, `maint_margin_used_base_ccy`
- `available_funds`, `available_funds_base_ccy`, `excess_liquidity`, `excess_liquidity_base_ccy`
- `maint_deficit_base_ccy`, `init_deficit_base_ccy`, `is_under_maintenance`
- `deposit!`, `withdraw!`, `accrue_interest!`, `accrue_borrow_fees!`, `apply_funding!`
- `register_instrument!`, `get_position`, `is_exposed_to`, `create_order!`, `oid!`, `format_datetime`
- `liquidate_all!`, `liquidate_to_maintenance!`

## Position analytics

- `has_exposure`, `value_quote`, `pnl_quote`

## Contract math

- `calc_value_quote`, `calc_pnl_quote`
- `option_intrinsic_value`, `option_underlying_price`, `update_option_underlying_price!`
- `margin_init_margin_ccy`, `margin_maint_margin_ccy`

## Exchange rate utilities

- `get_rate`, `get_rates_matrix`, `update_rate!`

## Portfolio logic

- `update_marks!`, `settle_expiry!`, `settle_option_expiry!`

## Target-weight portfolio management

- `Portfolio`, `TargetWeights`, `RebalancePolicy`, `RollTransition`, `RebalanceResult`
- `AccountSnapshot`, `PortfolioExposure`, `account_snapshot`, `portfolio_exposure`, `rebalance!`
- `FillContext`, `ModelFill`, `AbstractFillModel`, `TopOfBookFillModel`, `SpreadFillModel`, `model_fill`

## Collectors

- `PeriodicValues`, `PredicateValues`, `DrawdownValues`, `PortfolioWeightsValues`, `TurnoverValues`, `DrawdownMode`, `TurnoverMode`, `dates`
- `periodic_collector`, `predicate_collector`, `drawdown_collector`, `portfolio_weights_collector`, `turnover_collector`, `should_collect`
- `MinValue`, `MaxValue`, `min_value_collector`, `max_value_collector`

## Event driver

- `MarkUpdate`, `OptionUnderlyingUpdate`, `FundingUpdate`, `FXUpdate`
- `advance_time!`, `process_step!`, `process_expiries!`

## Backtesting

- `batch_backtest`

## Tables integration

- `balances_table`, `equities_table`, `positions_table`, `trades_table`, `cashflows_table`

## Analytics

- `performance_summary`, `performance_summary_table`
- `PerformanceSummary`, `TradeSummary`, `QuoteTradeSummary`, `SettlementTradeSummary`, `RealizedHoldingPeriod`, `HoldingPeriodSummary`
- `gross_realized_pnl_quote`, `net_realized_pnl_quote`
- `trade_summary`, `realized_holding_periods`, `holding_period_summary`, `pnl_concentration`

## Formatting helpers

- `format_cash`, `format_base`, `format_quote`
- `calc_base_qty_for_notional`
- `has_expiry`, `is_expired`, `is_active`, `ensure_active`
- `spot_instrument`, `perpetual_instrument`, `future_instrument`, `option_instrument`

## Printing helpers

- `print_cash_balances`, `print_equity_balances`, `print_positions`, `print_trades`, `print_cashflows`

## Utilities

- `params_combinations`

## Plotting

All helpers below belong to `Fastback` and use the selected backend. SVG is
built in and selected by default. See [SVG plotting](plotting/gen/1_svg.md).

- `plot_backend()`, `set_plot_backend!(:svg | :plots)`: read or select the global backend.
- `svg_output_format()`, `set_svg_output_format!(:string | :html)`: select inline `Base.HTML` results (default) or raw SVG strings.

Every plotting call accepts a `backend=:svg` or `:plots` override without
changing the global setting. SVG calls also accept `output_format=:string` or
`:html`. SVG `!` methods take an IO and write a complete SVG document; the
output-format setting does not affect them.

- `plot_title`
- `plot_balance`, `plot_balance!`
- `plot_equity`, `plot_equity!`
- `plot_open_orders_count`, `plot_open_orders_count!`
- `plot_drawdown`, `plot_drawdown!`
- `plot_equity_drawdown`, `plot_equity_drawdown!`
- `plot_exposure`, `plot_exposure!`
- `plot_portfolio_weights_over_time`
- `plot_cashflows`
- `plot_realized_cum_returns_by_hour`
- `plot_realized_cum_returns_by_weekday`

## Optional Plots.jl extension

Run `using Plots`, then `Fastback.set_plot_backend!(:plots)` to use the same
`Fastback.plot_*` functions with Plots.jl output. Loading Plots alone does not
change the default. Selecting it before loading the package raises an error
with setup instructions.

The Plots backend supports `!` overlays for balance, equity, open orders,
drawdown, equity/drawdown, and exposure on an existing `Plots.Plot`. The other
`!` helpers are SVG-only. A call's selected backend must match its IO or plot
target; use `backend=` when working with both backends. See the
[Plots.jl showcase](plotting/gen/2_plots_extension.md).
