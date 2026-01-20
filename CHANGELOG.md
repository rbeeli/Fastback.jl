# Changelog

All notable changes to this project will be documented in this file.

## [0.5.0] - 2026-01-20

### Added

- Support for optional Instrument `multiplier` value
- `Position.value_local` and `update_valuation! = update_pnl!` functions
- `SettlementType` enum for specifying settlement types of instruments (Asset vs. Cash)
- `MarginMode` enum + `update_margin!` + `update_marks!` functions for margin calculations and extended `Position` struct and `Account` struct to support margin trading

### Changed

- Quote cash lookup performance improvement by caching index in `Instrument` struct

## [0.4.2] - 2025-09-29

### Changed

- Improve printing in `show(acc)` of trades and positions by showing first and last few entries when there are many, not only the first few

## [0.4.1] - 2025-09-28

### Added

- New field `Position.last_order` for tracking the last order that modified the position
- New field `Position.last_trade` for tracking the last trade that modified the position

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
