# Fastback.jl - Blazing fast Julia backtester 🚀

Fastback provides a lightweight, flexible and highly efficient event-based backtesting library for quantitative trading strategies.

The main value of Fastback is provided by the account and bookkeeping implementation.
It keeps track of the open positions, account balance and equity.
Furthermore, the execution logic supports fees, slippage, partial fills and execution delays in its design.

Fastback does not try to model every aspect of a trading system, e.g. brokers, data sources, logging etc.
Instead, it provides basic building blocks for creating a custom backtesting environment that is easy to understand and extend.
For example, Fastback has no notion of "strategy" or "indicator", such constructs are highly strategy implementation specific and therefore up to the user to define.

The event-based architecture aims to mimic the way a real-world trading systems works, where new data is ingested as a continuous data stream, i.e. events.
This reduces the implementation gap from backtesting to real-world execution significantly compared to a vectorized backtesting frameworks.

## Bug reports and feature requests

Please report any issues via the GitHub issue tracker.
