# Getting started

This page gets you to a running backtest in a few minutes.

## Install

```julia
using Pkg
Pkg.add("Fastback")
```

Optional plotting extras:

```julia
using Pkg
Pkg.add(["Plots", "StatsPlots"])
```

## Hello world backtest

The example below runs a tiny event-driven loop, marks positions each step,
and opens and closes a single position.

```@example
using Fastback
using Dates

# 1) Account and cash
acc = Account(;
    mode=AccountMode.Cash,
    base_currency=CashSpec(:USD),
    broker=FlatFeeBroker(pct=0.001),
)
usd = cash_asset(acc, :USD)
deposit!(acc, usd, 10_000.0)

# 2) Instrument (spot, cash-settled synthetic exposure)
ABC = register_instrument!(acc, spot_instrument(:ABC, :ABC, :USD))

# 3) Small price series
dts = [DateTime(2024, 1, 1) + Hour(i) for i in 0:5]
prices = [100.0, 101.0, 99.5, 102.0, 101.0, 103.0]

collect_equity, equity_data = periodic_collector(Float64, Hour(1))

for (dt, price) in zip(dts, prices)
    # Mark to market at each step (bid/ask/last are equal here for simplicity).
    update_marks!(acc, ABC, dt, price, price, price)

    if dt == dts[2] # open
        order = Order(oid!(acc), ABC, dt, price, 10.0)
        fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price)
    elseif dt == dts[5] # close
        pos = get_position(acc, ABC)
        order = Order(oid!(acc), ABC, dt, price, -pos.quantity)
        fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price)
    end

    if should_collect(equity_data, dt)
        collect_equity(dt, equity(acc, usd))
    end
end

equity(acc, usd)

# optional plot (requires Plots.jl)
using Plots
Fastback.plot_equity(equity_data)
```

## Next steps

- Read [Basic setup](basic_setup.md) for a checklist of the typical backtest components.
- Read [Accounting model and event loop](concepts.md) to understand balances, equity, margin, and marks.
- Browse the Examples for end-to-end strategies and integrations.
