# Changelog

All notable changes to this project will be documented in this file.

## [0.9.0] - 2026-05-04

### Added

- Basic listed option support via `ContractKind.Option`, `OptionRight`, `OptionExerciseStyle`, and `option_instrument`.
- Quote-driven option premium accounting, underlying mark updates through `OptionUnderlyingUpdate`, and cash-settled option expiry via `settle_option_expiry!`.
- Conservative short-option margin with instrument-level `option_short_margin_rate` and `option_short_margin_min_rate` parameters, plus bounded multi-leg option margin relief for spreads, butterflies, and condors.
- `fill_option_strategy!` for atomic multi-leg option fills checked against final package buying power.
- IBKR Pro Fixed option commissions with premium tiers and per-order minimums.

## [0.8.0] - 2026-05-03

### Added

- `PerformanceSummary` now includes additional equity-curve diagnostics, changing positional construction and the exact `performance_summary_table` schema.
- `performance_summary` now reports `n_periods`, `best_ret`, `worst_ret`, `positive_period_rate`, `expected_shortfall_95`, `skewness`, `kurtosis`, `downside_vol`, `max_dd_duration`, `pct_time_in_drawdown`, and `omega`.
- `performance_summary_table` exposes the new `PerformanceSummary` fields as Tables.jl columns.

## [0.7.0] - 2026-04-12

### Added

- `PerformanceSummary`, `TradeSummary`, `QuoteTradeSummary`, `SettlementTradeSummary`, `RealizedHoldingPeriod`, and `HoldingPeriodSummary` result types with explicit fields and compact REPL display.
- `performance_summary`, `trade_summary`, `realized_holding_periods`, `holding_period_summary`, and `pnl_concentration` analytics helpers.
- `gross_realized_pnl_quote` and `net_realized_pnl_quote` helpers for quote-currency realized P&L diagnostics.
- `performance_summary_table` as a one-row Tables.jl source exposing the fields of `PerformanceSummary`, including trade diagnostics such as `n_trades`, `n_closing_trades`, `winners`, and `losers`.
- `performance_summary` returns unrounded numeric values with compact display, `trade_summary` groups quote- and settlement-currency diagnostics by currency, and `pnl_concentration` reports realized P&L concentration by bucket and quote currency.

## [0.6.0] - 2026-04-11

### Breaking changes ⚠️

- `Trade` now stores fill-time base-currency traded notional in the new `notional_base` field. Positional `Trade` construction must include this field.

### Added

- `turnover_collector`, `TurnoverValues`, and `TurnoverMode` for account-level turnover series. The collector tracks gross traded notional by period using fill-time base-currency notionals, reports round-trip turnover by default, supports one-way notional turnover via `TurnoverMode.OneWay`, returns `NaN` for nonpositive base-currency equity, and includes the turnover mode in Tables.jl rows.

## [0.5.1] - 2026-03-23

### Changed

- `Cashflow` struct immutable now.
- `Account` constructor parameters `track_trades` and `track_cashflows` to optionally switch off tracking of trades and cashflows. New `trade_count` field that's always populated, even if `track_trades=false`.

## [0.5.0] - 2026-02-15

### Breaking changes ⚠️

- Complete rework of the API with lots of renamings, restructuring and new features.
- Introduction of margin- and futures trading support as first-class concepts.
- Introduction of broker concept.

## [0.4.0] - 2025-09-26

### Breaking changes ⚠️

- `Account` now only uses keyword arguments in constructor
- Renamings for clarity (update any usages accordingly!):

    `cash` -> `cash_balance`

    `cash_object` -> `cash_asset`

    `hash_cash_symbol` -> `has_cash_asset`

    `format_date` -> `format_datetime`

    `register_cash!` -> `register_cash_asset!`

- Split `add_cash!` function into `deposit!` and `withdraw!`  (update any usages accordingly!)
- `should_collect` function must be called for all collectors to determine if a value should be collected
- `predicate` parameter removed from `drawdown_collector` function, only `Period` remains supported

### Added

- Add [Tables.jl](https://github.com/JuliaData/Tables.jl) integration for account artefacts and collectors
- New Glossary page in docs
- Generalized support for arbitrary `Dates.AbstractTime` types across the package for date/time handling instead of just `DateTime`
- Example integrations for `NanoDates.jl` and `Timestamps64.jl` time provider packages

### Changed

- Consistently use of `qty` instead of `quantity` for display outputs
- Explicitly export all public API functions in `Fastback.jl`

## [0.3.0] - 2025-09-25

- Introduce optional take_profit and stop_loss fields for Order
- Switch to [TestItemRunner.jl](https://github.com/julia-vscode/TestItemRunner.jl) for unit tests

## [0.2.0] - 2025-09-23

- Update code to integrate PrettyTables v3 due to breaking changes
- Set PrettyTables v3 compatibility constraint in Project.toml

## [0.1.0] - 2025-07-23

- First release
