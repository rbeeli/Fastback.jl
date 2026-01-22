# Fastback.jl - Blazingly fast Julia backtester 🚀

[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/rbeeli/Fastback.jl/blob/main/LICENSE)
![Maintenance](https://img.shields.io/maintenance/yes/2025)
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

- Event-based, modular architecture
- Multi-currency support
  - Hold multiple cash assets in parallel, e.g. USD, EUR, BTC etc.
  - Trade instruments with different quote currencies corresponding to the account currencies
  - Helpers for currency conversion
- Supports arbitrary price data sources
- Supports modelling commissions, execution delays, price slippage and partial fills
- Flexible data collectors to historize account balances, drawdowns, etc.
- Facilities for parallelized backtesting and hyperparameter optimization
- Uses position netting approach for bookkeeping
  - Maintains single position per instrument using weighted average cost method
- Integrations
  - [Tables.jl](https://github.com/JuliaData/Tables.jl) integration for `Account` related data like trades, positions, balances, etc.
  - [NanoDates.jl](https://juliatime.github.io/NanoDates.jl/stable/) integration for nanosecond-resolution timestamps
  - [Timestamps64.jl](https://rbeeli.github.io/Timestamps64.jl/stable/) integration for more efficient nanosecond-resolution timestamps

## Documentation & Examples

Full documentation and examples are available at [Fastback.jl documentation page](https://rbeeli.github.io/Fastback.jl/).

## Changelog

See the [CHANGELOG](https://github.com/rbeeli/Fastback.jl/blob/main/CHANGELOG.md).

## Bug reports and feature requests

Please report any issues via the [GitHub issue tracker](https://github.com/rbeeli/Fastback.jl/issues).
