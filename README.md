# Fastback.jl - Blazing fast Julia backtester 🚀

[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
![Maintenance](https://img.shields.io/maintenance/yes/2024)

Fastback provides a lightweight, flexible and highly efficient event-based backtesting framework for quantitative trading strategies.

Fastback does not try to model every aspect of a trading system, e.g. brokers, data sources, logging etc., but rather provides basic building blocks to create a custom backtesting environment that is easy to understand and extend.

## Features

- Event-based
- Modular architecture, no opinionated black-box design
- Supports arbitrary pricing data source
- Supports modelling fees, execution delays, price slippage and partial fills
- Flexible data collectors to collect time series like account equitity history, number of open positions, etc.
- Uses position netting approach for bookkeeping
  - Maintains single position per instrument using weighted average cost method
