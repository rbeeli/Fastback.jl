# Changelog

All notable changes to this project will be documented in this file.

## [0.11.0] - 2026-09-05

### Breaking changes ⚠️

- Removed esoteric `plot_violin_realized_returns_by_day` and `plot_violin_realized_returns_by_hour`, their exports and examples, and the optional StatsPlots dependency.
- `Fastback.plot_*` now uses built-in SVG by default. To retain Plots.jl output, run `using Plots` and `set_plot_backend!(:plots)`, or pass `backend=:plots` to individual calls.

### Added

- A unified `Fastback.plot_*` interface with built-in SVG rendering and optional Plots.jl output, selected globally through `set_plot_backend!` or per call with `backend`.
- SVG strings and IO-first `!` methods for balance, equity, open orders, drawdown, exposure, portfolio weights, cashflows, and cumulative realized returns, without additional dependencies.
- SVG plots return inline `Base.HTML` results by default. Use `set_svg_output_format!(:string)` for raw SVG strings or `:html` to restore inline display; individual calls accept an `output_format` override.
- Dark SVG presentation theme, separate equity/drawdown axes, maximum-drawdown markers, and stacked portfolio weights.

### Changed

- Require RiskPerf 0.4, which replaces Distributions with StatsFuns and reduces package loading overhead.
- SVG is the primary plotting approach in the README, quickstarts, API guide, and plotting showcases; Plots.jl remains an optional extension.
- Both plotting backends select maximum-drawdown markers by the collector's mode and use non-negative default limits with a bounded number of integer ticks for open-order counts.

## [0.10.0] - 2026-09-01

### Breaking changes ⚠️

- Fastback now requires Julia 1.12 or later; older Julia releases are no longer supported.
- Variation-margin `Trade.fill_pnl_settle` now attributes previously settled mark-to-market P&L to reductions and final expiry. Opening execution-to-mark cash still settles immediately, but remains attached to the open position until exposure is realized. As a result, gross trade P&L and same-fill cash movement can differ.
- Account operations now enforce non-decreasing time consistently. Backdated fills, marks, financing calls, lifecycle operations, and event steps are rejected.
- Direct `update_rate!(acc, ...)` calls are rejected while exposure is open; use `process_step!(...; fx_updates=...)` so dependent values and margins are revalued together.
- `process_step!` and multi-stage lifecycle operations are fail-stop rather than transactional. If one fails, completed changes remain and the account is marked `poisoned`; discard it rather than continuing the backtest.
- `Trade` has a new `preceding_split_factor` field for split-aware analytics. The previous positional constructor remains available and defaults the factor to `1.0`.
- `performance_summary` now interprets `risk_free` and `mar` as annualized simple rates and converts them to per-period thresholds using `periods_per_year`.

### Added

- Optional target-weight portfolio management with `Portfolio`, `TargetWeights`, `RebalancePolicy`, deterministic fill models, explicit futures/perpetual rolls, fully funded cash scaling, exposure snapshots, and reduction-first execution.
- `apply_spot_corporate_action!` for spot splits, reverse splits, and signed cash dividends, including `CashflowKind.CashDividend` and split-aware holding-period reconstruction.
- `AccountPoisonedError` identifies attempts to advance a failed account.
- Boundary validation for fill quantities and ownership, crossed quotes, cash amounts, instrument metadata, exchange rates, and conversion overflows.

### Changed

- `process_step!` coalesces repeated FX, mark, and option-underlying observations with last-observation-wins semantics without copying account-wide state.
- Duplicate market observations are indexed by route, option chain, or instrument, making coalescing linear in the event count.
- `process_expiries!` settles short options first, futures second, and long options last, preserving registration order within each priority group.
- `create_order!` validates account-owned strategy orders, assigns their IDs, and advances account time at order creation; direct `Order(...)` construction remains available as a low-level compatibility path.
- Ordinary fills now plan mark settlement, borrow fees, execution effects, margin, and trade notional before committing; a failed fill leaves marks, cash, positions, financing clocks, and history unchanged.
- Futures/option expiry batches, rolls, liquidation, and corporate actions retain completed changes and poison the account when any later stage fails.
- Exchange-rate updates reject Float64 values whose reciprocal is not finite before resizing or changing the rate matrix.
- `StepSchedule` sorts breakpoints and rejects empty schedules and duplicate timestamps.
- `check_invariants` independently recomputes position values and portfolio margins and now audits registry layout, flat-position state, ledger numerics, and history ordering.
- `calc_base_qty_for_notional` uses tolerance-aware tick arithmetic and clamps to inward tick-aligned quantity bounds.
- Hot fill and mark paths no longer rescan every derived field for finiteness; critical input, route, conversion, and ledger boundaries remain validated.

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
