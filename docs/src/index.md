# Fastback.jl - Blazingly fast Julia backtester 🚀

[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/rbeeli/Fastback.jl/blob/main/LICENSE)
![Maintenance](https://img.shields.io/maintenance/yes/2025)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://rbeeli.github.io/Fastback.jl/)

Fastback provides a lightweight, flexible and highly efficient event-based backtesting library for quantitative trading strategies.

## Why Fastback?

**Event-driven architecture**: Unlike vectorized backtesting frameworks, Fastback mimics real-world trading systems where data arrives as a continuous stream of events. This significantly reduces the implementation gap between backtesting and live trading.

**Sophisticated bookkeeping**: At its core, Fastback provides robust account and position management with support for commissions, slippage, partial fills, and execution delays—all essential for realistic backtesting.

**Modular design**: Fastback focuses on providing fundamental building blocks rather than prescriptive frameworks. There's no built-in notion of "strategy" or "indicator"—you define these concepts according to your needs.

## Key Features

### Core Capabilities
- **Event-based processing**: Stream-oriented data handling that mirrors production systems
- **Position netting**: Maintains single position per instrument using weighted average cost method
- **Multi-currency support**: Trade instruments in different currencies with built-in conversion helpers
- **Flexible data sources**: Works with DataFrames, CSV files, databases, or any iterable data structure

### Trading Realism
- **Commission modeling**: Fixed and percentage-based commission structures
- **Execution delays**: Model order-to-fill latency for realistic backtesting
- **Price slippage**: Account for market impact and bid-ask spreads
- **Partial fills**: Support for incomplete order execution

### Performance & Extensibility
- **Type-safe metadata**: Attach custom data to instruments, orders, and cash assets
- **Parallelized backtesting**: Built-in support for parameter optimization across multiple cores
- **Data collection**: Flexible collectors for equity curves, drawdowns, and custom metrics
- **Tables.jl integration**: Seamless interoperability with the Julia data ecosystem

### Integrations
- **[Tables.jl](https://github.com/JuliaData/Tables.jl)**: Zero-copy views of trades, positions, and balances
- **[NanoDates.jl](https://juliatime.github.io/NanoDates.jl/stable/)**: Nanosecond-resolution timestamps with extended range
- **[Timestamps64.jl](https://rbeeli.github.io/Timestamps64.jl/stable/)**: High-performance nanosecond timestamps

## Quick Start

```julia
using Fastback

# 1. Create and fund account
account = Account()
usd = Cash(:USD, digits=2)
deposit!(account, usd, 100_000.0)

# 2. Register instrument
aapl = Instrument(:AAPL, :USD, base_digits=0, quote_digits=2)
register_instrument!(account, aapl)

# 3. Execute a trade
order = Order(oid!(account), aapl, DateTime("2023-01-01"), 150.0, 100.0)
trade = fill_order!(account, order, DateTime("2023-01-01"), 150.50; commission=1.0)

# 4. Check results
print_positions(account)
print_cash_balances(account)
```

## Getting Started

**New to Fastback?** Start with our [Basic Setup Guide](basic_setup.md) for a step-by-step introduction.

**Learn by example**: Explore our comprehensive [Examples](examples/gen/1_random_trading.md) covering everything from simple strategies to advanced multi-currency portfolios.

**Need specific functionality?** Check the [API Reference](api.md) for detailed documentation of all functions and types.

## Documentation Structure

This documentation is organized into several sections:

- **[Basic Setup](basic_setup.md)**: Step-by-step guide to building your first backtest
- **[Examples](examples/gen/1_random_trading.md)**: Working examples of increasing complexity
- **[API Reference](api.md)**: Comprehensive function and type documentation
- **[Integrations](integrations.md)**: Working with Tables.jl, NanoDates.jl, and other packages
- **[Glossary](glossary.md)**: Definitions of key concepts and terminology

## Performance Considerations

Fastback is designed for speed and efficiency:

- **Minimal allocations**: Core trading operations avoid unnecessary memory allocation
- **Type stability**: All critical paths are type-stable for optimal performance
- **Vectorized operations**: Built-in support for batch processing where appropriate
- **Parallel execution**: Use `batch_backtest` for parameter optimization across multiple cores

## Community & Support

- **Issues & Feature Requests**: [GitHub Issue Tracker](https://github.com/rbeeli/Fastback.jl/issues)
- **Changelog**: [Release History](https://github.com/rbeeli/Fastback.jl/blob/main/CHANGELOG.md)
- **Contributing**: Contributions welcome! Please see our contribution guidelines

## License

Fastback.jl is released under the [MIT License](https://github.com/rbeeli/Fastback.jl/blob/main/LICENSE).
