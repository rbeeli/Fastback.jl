# Changelog

All notable changes to this project will be documented in this file.

## [0.4.0] - 2025-09-25

### Breaking changes ⚠️

- Renaming of `hash_cash_symbol` to `has_cash_symbol` due to typo
- `Account` now only using keyword arguments for constructor

### Added

- Add [Tables.jl](https://github.com/JuliaData/Tables.jl) integration for account artefacts and collectors

## [0.3.0] - 2025-09-25

- Introduce optional take_profit and stop_loss fields for Order
- Switch to [TestItemRunner.jl](https://github.com/julia-vscode/TestItemRunner.jl) for unit tests

## [0.2.0] - 2025-09-23

- Update code to integrate PrettyTables v3 due to breaking changes
- Set PrettyTables v3 compatibility constraint in Project.toml

## [0.1.0] - 2025-07-23

- First release
