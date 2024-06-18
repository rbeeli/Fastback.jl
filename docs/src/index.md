# Fastback.jl - Blazingly fast Julia backtester 🚀

Fastback provides a lightweight, flexible and highly efficient event-based backtesting library for quantitative trading strategies.

The main value of Fastback is provided by the account and bookkeeping implementation.
It keeps track of the open positions, account balance and equity.
Furthermore, the execution logic supports commissions, slippage, partial fills and execution delays in its design.

Fastback does not try to model every aspect of a trading system, e.g. brokers, data sources, logging etc.
Instead, it provides basic building blocks for creating a custom backtesting environment that is easy to understand and extend.
For example, Fastback has no notion of "strategy" or "indicator", such constructs are highly strategy specific, and therefore up to the user to define.

The event-based architecture aims to mimic the way a real-world trading systems works, where new data is ingested as a continuous data stream, i.e. events.
This reduces the implementation gap from backtesting to real-world execution significantly compared to a vectorized backtesting frameworks.

### Features

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

### Bug reports and feature requests

Please report any issues via the [GitHub issue tracker](https://github.com/rbeeli/Fastback.jl/issues).
