# Changelog

All notable changes to this project will be documented in this file.

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

### Added

- Add [Tables.jl](https://github.com/JuliaData/Tables.jl) integration for account artefacts and collectors
- New Glossary page in docs

### Changed

- Consistently use of `qty` instead of `quantity` for display outputs

## [0.3.0] - 2025-09-25

- Introduce optional take_profit and stop_loss fields for Order
- Switch to [TestItemRunner.jl](https://github.com/julia-vscode/TestItemRunner.jl) for unit tests

## [0.2.0] - 2025-09-23

- Update code to integrate PrettyTables v3 due to breaking changes
- Set PrettyTables v3 compatibility constraint in Project.toml

## [0.1.0] - 2025-07-23

- First release
