# AGENTS – Fastback.jl

Working notes for agents contributing to this repository.
Keep it concise, keep it accurate, and keep the core trading/accounting invariants intact.

## Project snapshot

- Event-driven backtesting library for quantitative trading written in Julia.
- Single netted `Position` per instrument; account state lives in `Account` (balances, equities, margin vectors, trades, positions).
- Multi-currency aware; instruments carry settlement style, margin mode, lifecycle (start/expiry), and optional contract multiplier. Margining can be per-currency or base-currency.
- Public API is centralized in `src/Fastback.jl` (exports and type aliases `Price`/`Quantity` = `Float64`).

## Repo map

- `src/`: core types and logic  
  - `account.jl`: account state, cash register/deposit/withdraw, position lookup; keep `balances` and `equities` updated together.  
  - `instrument.jl`: instrument metadata, lifecycle checks (`has_expiry`, `is_active`, `ensure_active`).  
  - `order.jl`, `trade.jl`, `position.jl`: order/trade data and position math; positions are netted, average price must stay consistent.  
  - `logic.jl`: P&L, valuation, margin updates, fill pipeline (`fill_order!`); settlement styles (`Asset`, `Cash`, `VariationMargin`) drive cash/equity handling.  
  - `exchange_rates.jl`: currency conversion helpers and rate storage.  
  - `margin.jl`: base-currency margin metrics (`*_base_ccy`, maintenance/init deficits).  
  - `liquidation.jl`: deterministic `liquidate_all!` using mark prices and liquidation trade reason.  
  - `collectors.jl`, `tables.jl`, `print.jl`: data collection, Tables.jl outputs, formatted printing.  
  - `backtest_runner.jl`: threaded batch runner (`Threads.@threads`); avoid global state in callbacks.  
  - `utils.jl`: `params_combinations`, ETA formatting, misc helpers.  
- `test/`: uses TestItemRunner and `@testitem` blocks; reconciliation data lives in `test/data/`.  
- `docs/`: Documenter + Literate; examples in `docs/src/examples` are rendered to `docs/src/examples/gen` by `docs/make.jl`.  
- `justfile`: shortcuts for docs (`just build-docs`, `just serve-docs`).  
- `CHANGELOG.md`: release history; update alongside version bumps in `Project.toml`.

## Setup

- Julia 1.9+ (per `Project.toml` compat).  
- Install deps: `julia --project -e 'using Pkg; Pkg.instantiate()'`.  
- For docs: `just build-docs` (installs/uses docs environment), live preview `just serve-docs` (needs `npx live-server`).
- Note that docs has its own project environment inside the `docs` folder.

## Testing

- Full suite: `julia --project -e 'using Pkg; Pkg.test()'` (runs TestItemRunner).  
- Targeted file: `julia --project -e 'using TestItemRunner; TestItemRunner.run_tests(\"test/account.jl\")'`.  
- Set `JULIA_NUM_THREADS` when touching threaded code; keep tests deterministic.

## Coding conventions

- Opt for efficient algorithms and approaches; prioritize clarity where possible.
- Maintain `Price`/`Quantity` as `Float64`; keep structs concrete for performance.  
- Follow existing docstring style (triple quotes, short summary, brief args/returns) and liberal `@inline` on tiny helpers.  
- Preserve Tables.jl schemas (`balances_table`, `positions_table`, etc.) and PrettyTables formatting behavior.  
- Add new public symbols to `src/Fastback.jl` exports; mirror changes in docs/examples if user-facing.  
- No formatter configured—match existing spacing/line breaks; prefer 4-space indent and explicit typing.

## Docs workflow

- Add/modify examples in `docs/src/examples/*.jl`; register them in `docs/make.jl` so both markdown and notebooks regenerate.  
- Regenerate docs after user-facing changes; assets/styles live under `docs/src/assets/`.  
- Keep README badge/version in sync when releasing.

## Quality expectations

- Add `@testitem` coverage near changed code; use deterministic fixtures.  
- Guard against regressions in P&L, margin, and settlement math; compare to existing tests for patterns (`test/account.jl`, `test/position.jl`).  
- Avoid shared mutable state in threaded workflows (`batch_backtest`, collectors).  
- For releases: bump `Project.toml` version, update `CHANGELOG.md` (YYYY-MM-DD), and note breaking changes explicitly.
