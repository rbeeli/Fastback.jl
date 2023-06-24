# Fastback.jl - Blazing fast Julia backtester

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

🚀 `Fastback.jl` provides a lightweight, flexible and highly efficient event-based backtesting framework for quantitative trading strategies.

# Key features

* Event-based
* Realistic execution through use of order book
* Single position per asset through netting using Weighted Average Price method
* Supports arbitrary data source
* Fast, flexible, lightweight


<!--
# Minimal example

```julia

```
-->


# Development

## Testing

To run a subset of unit tests, call `Pkg.test` as follows, e.g. to run the tests in `test/utils.jl`:

```julia
import Pkg; Pkg.test("Fastback", test_args=["utils.jl"])
```

# TODO

* Commissions / fees
* Order book updates