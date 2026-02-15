# AGENTS – Fastback.jl

Working notes for agents contributing to this repository.
Keep it concise, keep it accurate, and keep the core trading/accounting invariants intact.

## Project snapshot

- Event-driven backtesting library for quantitative trading written in Julia.
- Single netted `Position` per instrument; account state lives in `Account` + `CashLedger` (balances, equities, margin vectors, trades, positions, cashflows).
- Multi-currency aware; instruments carry lifecycle, contract kind, and settlement style (`PrincipalExchange` or `VariationMargin`), with margining per-currency or base-currency.
- Broker hooks drive commissions and financing schedules.
- Public API is centralized in `src/Fastback.jl` (exports and type aliases `Price`/`Quantity` = `Float64`).

## Repo map

- `src/`: core types and logic  
  - `Fastback.jl`: module includes + public exports.
  - `enums.jl`, `errors.jl`: enum definitions and reject/error types.
  - `cash.jl`, `cashflows.jl`, `account.jl`, `exchange_rates.jl`: cash ledger, cashflow records, account state, FX conversion helpers.
  - `instrument.jl`, `order.jl`, `trade.jl`, `position.jl`: instrument metadata/lifecycle and order-trade-position math (netted exposure + stable average price semantics).
  - `contract_math.jl`, `execution.jl`, `risk.jl`, `logic.jl`: pure settlement math, fill planning, risk checks, valuation/margin pipeline (`fill_order!`, `roll_position!`, `settle_expiry!`).
  - `interest.jl`, `borrow_fees.jl`, `funding.jl`: financing accruals and funding cashflows.
  - `events.jl`: typed event driver (`MarkUpdate`, `FundingUpdate`, `FXUpdate`) and `process_step!` loop helpers.
  - `margin.jl`, `liquidation.jl`, `invariants.jl`: base-currency margin metrics, liquidation helpers, and account consistency checks.
  - `broker/*.jl`: broker fee/financing profiles (`NoOp`, `FlatFee`, `IBKRProFixed`, `Binance`).
  - `collectors.jl`, `tables.jl`, `print.jl`, `analytics.jl`, `plots.jl`: collectors, Tables.jl views, pretty-printing, perf summary, plotting extension hooks.
  - `backtest_runner.jl`, `utils.jl`: threaded batch runner (`Threads.@threads`) and utility helpers.
- `test/`: uses TestItemRunner and `@testitem` blocks; reconciliation data lives in `test/data/`.  
- `ext/`: optional package extension(s), currently `FastbackPlotsExt.jl` for Plots/StatsPlots-backed plotting methods.  
- `docs/`: Documenter + Literate; examples in `docs/src/examples` (including nested example folders) are rendered to `docs/src/examples/gen` by `docs/make.jl`.  
- `justfile`: shortcuts for docs (`just build-docs`, `just serve-docs`).  
- `CHANGELOG.md`: release history; update alongside version bumps in `Project.toml`.

## Setup

- Julia 1.9+ (per `Project.toml` compat).  
- Install deps: `julia --project -e 'using Pkg; Pkg.instantiate()'`.  
- For docs: `just build-docs` (installs/uses docs environment).
- Note that docs has its own project environment inside the `docs` folder.

## Testing

- Full suite: `julia --project -e 'using Pkg; Pkg.test()'` (runs TestItemRunner).  
- Targeted file: `julia --project -e 'using TestItemRunner; TestItemRunner.run_tests(\"test/account.jl\")'`.  
- Set `JULIA_NUM_THREADS` when touching threaded code; keep tests deterministic.

## Coding conventions

- Opt for efficient algorithms and approaches; prioritize clarity where possible.
- Maintain `Price`/`Quantity` as `Float64`; keep structs concrete for performance.  
- Follow existing docstring style (triple quotes, short summary, brief args/returns) and liberal `@inline` on tiny helpers.  
- Keep settlement semantics explicit: principal-exchange vs variation-margin paths must stay separate and deterministic.
- Preserve Tables.jl schemas (`balances_table`, `positions_table`, etc.) and PrettyTables formatting behavior.  
- Add new public symbols to `src/Fastback.jl` exports; mirror changes in docs/examples if user-facing.  
- No formatter configured—match existing spacing/line breaks; prefer 4-space indent and explicit typing.

## Docs workflow

- Add/modify examples in `docs/src/examples` (flat `.jl` files or nested `*/main.jl` entrypoints); register them in `docs/make.jl` so both markdown and notebooks regenerate.  
- Regenerate docs after user-facing changes; assets/styles live under `docs/src/assets/`.  
- Keep README badge/version in sync when releasing.

## Quality expectations

- Add `@testitem` coverage near changed code; use deterministic fixtures.  
- Guard against regressions in P&L, margin, settlement math, and financing accruals; compare to existing tests for patterns (`test/account.jl`, `test/position.jl`, `test/settlement_semantics.jl`, `test/events.jl`).  
- Avoid shared mutable state in threaded workflows (`batch_backtest`, collectors).  
- If touching accounting internals, sanity-check with `check_invariants(acc)` in tests.
- For releases: bump `Project.toml` version, update `CHANGELOG.md` (YYYY-MM-DD), and note breaking changes explicitly.
