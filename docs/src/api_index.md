# API index

Exhaustive public API list (core + Plots extension).
For narrative guidance, see [How-to](how_to.md) and [Glossary](glossary.md).
For details, open the REPL and type `?symbol` to view docstrings.

## Core types and enums

- `Fastback`, `Price`, `Quantity`
- `TradeDir`, `SettlementStyle`, `MarginMode`, `MarginingStyle`, `ContractKind`, `AccountMode`, `CashflowKind`, `OrderRejectReason`, `OrderRejectError`, `TradeReason`
- `Cash`, `Instrument`, `Order`, `Trade`, `Cashflow`, `Position`, `Account`
- `ExchangeRates`, `OneExchangeRates`, `SpotExchangeRates`

## Trade direction helpers

- `trade_dir`, `is_long`, `is_short`, `opposite_dir`

## Order and trade utilities

- `symbol`, `nominal_value`, `FillPlan`, `plan_fill`, `fill_order!`
- `is_realizing`, `realized_return`, `cfid!`

## Account operations

- `cash_asset`, `has_cash_asset`, `has_base_ccy`, `register_cash_asset!`
- `cash_base_ccy`, `quote_cash`, `settle_cash`, `margin_cash`
- `get_rate_base_ccy`, `to_settle`, `to_quote`, `to_margin`, `to_base`
- `cash_balance`, `equity`, `equity_base_ccy`, `balance_base_ccy`
- `init_margin_used`, `init_margin_used_base_ccy`, `maint_margin_used`, `maint_margin_used_base_ccy`
- `available_funds`, `available_funds_base_ccy`, `excess_liquidity`, `excess_liquidity_base_ccy`
- `maint_deficit_base_ccy`, `init_deficit_base_ccy`, `is_under_maintenance`
- `deposit!`, `withdraw!`, `set_interest_rates!`, `accrue_interest!`, `accrue_borrow_fees!`, `apply_funding!`
- `register_instrument!`, `get_position`, `is_exposed_to`, `oid!`, `tid!`, `format_datetime`
- `liquidate_all!`, `liquidate_to_maintenance!`

## Position analytics

- `has_exposure`, `value_quote`, `pnl_quote`, `cash_delta_quote`, `calc_pnl_quote`, `calc_return_quote`
- `margin_init_margin_ccy`, `margin_maint_margin_ccy`, `margin_init_settle`, `margin_maint_settle`
- `calc_realized_qty`, `calc_exposure_increase_quantity`

## Exchange rate utilities

- `add_asset!`, `get_rate`, `get_rates_matrix`, `update_rate!`

## Portfolio logic

- `update_valuation!`, `update_margin!`, `update_marks!`, `settle_expiry!`

## Collectors

- `PeriodicValues`, `PredicateValues`, `DrawdownValues`, `DrawdownMode`, `dates`
- `periodic_collector`, `predicate_collector`, `drawdown_collector`, `should_collect`
- `MinValue`, `MaxValue`, `min_value_collector`, `max_value_collector`

## Event driver

- `MarkUpdate`, `FundingUpdate`, `FXUpdate`
- `advance_time!`, `process_step!`, `process_expiries!`

## Backtesting

- `batch_backtest`

## Tables integration

- `balances_table`, `equities_table`, `positions_table`, `trades_table`, `cashflows_table`

## Analytics

- `performance_summary_table`

## Formatting helpers

- `format_cash`, `format_base`, `format_quote`, `format_period_HHMMSS`
- `has_expiry`, `is_expired`, `is_active`, `ensure_active`, `is_margined_spot`
- `spot_instrument`, `margin_spot_instrument`, `perpetual_instrument`, `future_instrument`

## Printing helpers

- `print_cash_balances`, `print_equity_balances`, `print_positions`, `print_trades`, `print_cashflows`

## Utilities

- `params_combinations`, `compute_eta`

## Plots extension (requires Plots.jl; violins need StatsPlots)

- `plot_title`
- `plot_balance`, `plot_balance!`
- `plot_equity`, `plot_equity!`, `plot_equity_seq`
- `plot_open_orders`, `plot_open_orders!`, `plot_open_orders_seq`
- `plot_drawdown`, `plot_drawdown!`, `plot_drawdown_seq`
- `plot_equity_drawdown`, `plot_equity_drawdown!`
- `plot_exposure`, `plot_exposure!`
- `plot_violin_realized_returns_by_day`, `plot_violin_realized_returns_by_hour`
- `plot_realized_cum_returns_by_hour`
- `plot_realized_cum_returns_by_hour_seq_net`, `plot_realized_cum_returns_by_hour_seq_gross`, `plot_realized_cum_returns_by_hour_seq`
- `plot_realized_cum_returns_by_weekday`, `plot_realized_cum_returns_by_weekday_seq`
