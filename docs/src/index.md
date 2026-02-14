# Fastback.jl - Blazingly fast Julia backtester 🚀

[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/rbeeli/Fastback.jl/blob/main/LICENSE)
![Maintenance](https://img.shields.io/maintenance/yes/2026)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://rbeeli.github.io/Fastback.jl/)

Fastback provides a lightweight, flexible and highly efficient event-based backtesting library for quantitative trading strategies.

Fastback focuses on deterministic accounting: it tracks open positions, balances, equity, margin, and cashflows across multiple currencies.
The execution pipeline supports broker-driven commissions/financing and partial fills; slippage and delays are modeled by the timestamps and fill prices you pass in.

Fastback does not try to model every aspect of a trading system, e.g. data ingestion, strategy logic, OMS/execution gateways, or logging.
Instead, it provides basic building blocks for creating a custom backtesting environment that is easy to understand and extend.
Broker behavior is intentionally lightweight and pluggable via broker profiles (for commissions and financing schedules).
For example, Fastback has no notion of "strategy" or "indicator"; such constructs are highly strategy specific, and therefore up to the user to define.

The event-based architecture aims to mimic how real-world trading systems ingest streaming data.
You drive the engine with explicit mark, FX, and funding updates, plus optional expiry and liquidation steps, which reduces the implementation gap to live execution compared to vectorized backtesting frameworks.

## Hello world backtest

```julia
using Fastback
using Dates

acc = Account(;
    broker=FlatFeeBrokerProfile(pct=0.001),
    mode=AccountMode.Cash,
    base_currency=CashSpec(:USD),
)
usd = cash_asset(acc, :USD)
deposit!(acc, usd, 10_000.0)
inst = register_instrument!(acc, spot_instrument(:ABC, :ABC, :USD))

dts = [DateTime(2024, 1, 1) + Hour(i) for i in 0:3]
prices = [100.0, 101.0, 102.0, 101.5]

collect_equity, equity_data = periodic_collector(Float64, Hour(1))

for (dt, price) in zip(dts, prices)
    update_marks!(acc, inst, dt, price, price, price)
    if dt == dts[1]
        order = Order(oid!(acc), inst, dt, price, 10.0)
        fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price)
    elseif dt == dts[end]
        pos = get_position(acc, inst)
        order = Order(oid!(acc), inst, dt, price, -pos.quantity)
        fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price)
    end

    if should_collect(equity_data, dt)
        collect_equity(dt, equity(acc, usd))
    end
end

equity(acc, usd)

# Plots (requires Plots.jl)
using Plots
Fastback.plot_equity(equity_data)
```

See [Getting started](getting_started.md) for a runnable walkthrough and next steps.

## Features

- Event-driven accounting engine with explicit event processing (`process_step!`) for marks, FX, funding, expiries, and optional liquidation
- Instruments: spot (including spot-on-margin), perpetuals, and futures with lifecycle guards (start/expiry), optional contract multipliers, and settlement styles (Asset/Variation Margin)
- Account modes: cash or margin; per-currency or base-currency margining; percent-notional or fixed-per-contract margin requirements
- Broker profiles for commissions/financing (e.g. flat-fee, IBKR-style, Binance-style)
- Multi-currency cash book with FX conversion helpers and base-currency metrics
- Execution & risk: broker-driven commissions, partial fills, liquidation-aware marking (bid/ask/last), and initial/maintenance margin checks
- Netted positions with weighted-average cost, realized/unrealized P&L, and a cashflow ledger + accrual helpers (lend/borrow interest, borrow fees on asset-settled spot shorts, funding, variation margin)
- Expiry handling for futures (auto-close via synthetic close) plus deterministic liquidation helpers
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
