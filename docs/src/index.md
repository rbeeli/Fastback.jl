# Fastback.jl - Blazing fast Julia backtester 🚀

Fastback provides a lightweight, flexible and highly efficient event-based backtesting framework for quantitative trading strategies.

Fastback does not try to model every aspect of a trading system, e.g. brokers, data sources, logging etc., but rather provides basic building blocks to create a custom backtesting environment that is easy to understand and extend.

The event-based architecture aims to mimic the way a real-world trading systems works, where new data is ingested as a continuous data stream, i.e. events. This reduces the implementation gap from backtesting to real-world execution significantly compared to a vectorized backtesting frameworks.

## Bug reports and feature requests

Please report any issues via the GitHub issue tracker.
