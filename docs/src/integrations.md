# Integrations

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
