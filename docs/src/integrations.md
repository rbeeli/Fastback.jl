# Integrations

## NanoDates.jl

Fastback provides seamless integration to all `Dates.AbstractTime` types, which includes [NanoDates.jl](https://juliatime.github.io/NanoDates.jl/stable/).
NanoDates.jl provides nanosecond-resolution timestamps at the cost of a larger memory footprint (16 bytes vs. 8 bytes compared to `DateTime`).
The representable date range is `-146138511-01-01T00:22:22` to `146138805-04-11T23:47:15`.

Example see [6_NanoDates_integration.jl](../examples/gen/6_NanoDates_integration.md).

## Timestamps64.jl

Fastback provides seamless integration to all `Dates.AbstractTime` types, which includes [Timestamps64.jl](https://rbeeli.github.io/Timestamps64.jl/stable/).
Timestamps64.jl provides nanosecond-resolution timestamps without sacrificing performance.
The `Timestamp64` type has a smaller memory footprint (8 bytes vs. 16 bytes compared to `NanoDate`), and is faster for arithmetic operations.
The representable date range is `1970-01-01T00:00:00` to `2262-04-11 23:47:16`.

Example see [7_Timestamps64_integration.md](../examples/gen/7_Timestamps64_integration.md).

## Tables.jl

Fastback ships with zero-copy views that make every major account artefact available through the **Tables.jl** interface.
That means you can hand results straight to DataFrames.jl, CSV.jl, Arrow.jl, or any other package that consumes Tables-compatible sources.

### Account

| accessor | description |
| --- | --- |
| `trades_table(acc)` | All executed trades with order, execution, and metadata fields |
| `positions_table(acc)` | Current positions |
| `balances_table(acc)` | Cash balances per currency, preserving custom cash metadata |
| `equities_table(acc)` | Equity values per currency |

```julia
using DataFrames
using Fastback

df_trades = DataFrame(trades_table(acc))
df_positions = DataFrame(positions_table(acc))
df_balances = DataFrame(balances_table(acc))
df_equities = DataFrame(equities_table(acc))
```

All helpers return read-through views, so changes to the underlying account are visible immediately without copying.

### Collectors

Time-series collectors already satisfy the Tables.jl contract, so you can hand
them directly to downstream packages.
Drawdown collectors behave the same way, preserving the configured mode in each row.

```julia
using Dates
using DataFrames
using Fastback

collect_equity, equity_data = periodic_collector(Float64, Hour(1))
collect_drawdown, drawdown_data = drawdown_collector(DrawdownMode.Percentage, Hour(1))

# ... run backtest and collect values ...

df_equity_history = DataFrame(equity_data)
df_drawdown_history = DataFrame(drawdown_data)
```
