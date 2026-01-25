# Fastback.jl - Blazingly fast Julia backtester 🚀

[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/rbeeli/Fastback.jl/blob/main/LICENSE)
![Maintenance](https://img.shields.io/maintenance/yes/2026)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://rbeeli.github.io/Fastback.jl/)

Fastback provides a lightweight, flexible and highly efficient event-based backtesting library for quantitative trading strategies.

The main value of Fastback is provided by the account and bookkeeping implementation.
It keeps track of the open positions, account balance and equity.
Furthermore, the execution logic supports commissions, slippage, partial fills and execution delays in its design.

Fastback does not try to model every aspect of a trading system, e.g. brokers, data sources, logging etc.
Instead, it provides basic building blocks for creating a custom backtesting environment that is easy to understand and extend.
For example, Fastback has no notion of "strategy" or "indicator", such constructs are highly strategy specific, and therefore up to the user to define.

The event-based architecture aims to mimic the way a real-world trading systems works, where new data is ingested as a continuous data stream, i.e. events.
This reduces the implementation gap from backtesting to real-world execution significantly compared to a vectorized backtesting frameworks.

## Features

- Event-based, modular architecture that mirrors streaming execution
- Spot, perpetual, and future instruments with lifecycle guards (start/expiry) and optional contract multipliers
- Asset, Cash, and Variation Margin settlement styles plus margin modes for mark-to-market and liquidation
- Multi-currency accounts
  - Hold multiple cash assets in parallel and trade instruments with different quote currencies
  - FX helpers and base-currency margin metrics
- Pluggable price data sources
- Execution modelling: commissions, delays, slippage, partial fills
- Netted positions per instrument using weighted average cost
- Data collectors for balances, equity, drawdowns, etc. with Tables.jl outputs
- Parallelized batch backtesting and hyperparameter sweeps
- Integrations
  - [Tables.jl](https://github.com/JuliaData/Tables.jl) for trades, positions, balances, collectors
  - [NanoDates.jl](https://juliatime.github.io/NanoDates.jl/stable/) for nanosecond timestamps
  - [Timestamps64.jl](https://rbeeli.github.io/Timestamps64.jl/stable/) for efficient nanosecond timestamps

## Documentation & Examples

Full documentation and examples are available at [Fastback.jl documentation page](https://rbeeli.github.io/Fastback.jl/).

## Changelog

See the [CHANGELOG](https://github.com/rbeeli/Fastback.jl/blob/main/CHANGELOG.md).

## Bug reports and feature requests

Please report any issues via the [GitHub issue tracker](https://github.com/rbeeli/Fastback.jl/issues).
