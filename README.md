# Fastback.jl - Blazingly fast Julia backtester 🚀

[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/rbeeli/Fastback.jl/blob/main/LICENSE)
![Maintenance](https://img.shields.io/maintenance/yes/2026)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://rbeeli.github.io/Fastback.jl/)

Fastback provides a lightweight, flexible and highly efficient event-based backtesting library for quantitative trading strategies.

Fastback focuses on deterministic accounting: it tracks open positions, balances, equity, margin, and cashflows across multiple currencies.
The execution pipeline supports fixed/percentage commissions and partial fills; slippage and delays are modeled by the timestamps and fill prices you pass in.

Fastback does not try to model every aspect of a trading system, e.g. brokers, data sources, logging etc.
Instead, it provides basic building blocks for creating a custom backtesting environment that is easy to understand and extend.
For example, Fastback has no notion of "strategy" or "indicator"; such constructs are highly strategy specific, and therefore up to the user to define.

The event-based architecture aims to mimic how real-world trading systems ingest streaming data.
You drive the engine with explicit mark, FX, and funding updates, plus optional expiry and liquidation steps, which reduces the implementation gap to live execution compared to vectorized backtesting frameworks.

## Features

- Event-driven accounting engine with explicit event processing (`process_step!`) for marks, FX, funding, expiries, and optional liquidation
- Instruments: spot, spot-on-margin, perpetuals, and futures with lifecycle guards (start/expiry), optional contract multipliers, settlement styles (Asset/Cash/Variation Margin), and cash/physical delivery
- Account modes: cash or margin; per-currency or base-currency margining; percent-notional or fixed-per-contract margin requirements
- Multi-currency cash book with FX conversion helpers and base-currency metrics
- Execution & risk: fixed/percentage commissions, partial fills, liquidation-aware marking (bid/ask/last), and initial/maintenance margin checks
- Netted positions with weighted-average cost, realized/unrealized P&L, and a cashflow ledger + accrual helpers (interest, borrow fees on asset-settled shorts, funding, variation margin)
- Expiry handling for futures (auto-close or error on physical delivery) plus deterministic liquidation helpers
- Collectors (periodic, predicate, drawdown, min/max) and Tables.jl views for balances, equity, positions, trades, cashflows; pretty-print helpers
- Batch backtesting and parameter sweeps with threaded runner and ETA logging
- Integrations
  - [Plots.jl](https://github.com/JuliaPlots/Plots.jl) and [StatsPlots.jl](https://github.com/JuliaPlots/StatsPlots.jl) for optional visualization helpers (via `FastbackPlotsExt`)
  - [NanoDates.jl](https://juliatime.github.io/NanoDates.jl/stable/) for nanosecond timestamps
  - [Timestamps64.jl](https://rbeeli.github.io/Timestamps64.jl/stable/) for efficient nanosecond timestamps

## Documentation & Examples

Full documentation and examples are available at [Fastback.jl documentation page](https://rbeeli.github.io/Fastback.jl/).

## Changelog

See the [CHANGELOG](https://github.com/rbeeli/Fastback.jl/blob/main/CHANGELOG.md).

## Bug reports and feature requests

Please report any issues via the [GitHub issue tracker](https://github.com/rbeeli/Fastback.jl/issues).
