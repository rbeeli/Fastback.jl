# Analytics

Fastback's analytics helpers are small diagnostics built on top of recorded
trades and collected account values. They do not change execution, accounting,
commissions, or settlement behavior.

Use them for quick checks after a backtest:

- performance summaries from return or equity series
- quote-currency realized P&L diagnostics from `Trade` records
- compact trade summaries
- FIFO holding-period reconstruction
- realized P&L concentration by instrument, period, or trade

## Performance Summary

`performance_summary(returns, config)` summarizes periodic simple returns and
`performance_summary_from_equity(equity, config)` a `PeriodicValues` equity
collector. Both return a `PerformanceSummary` with observation counts
(non-finite returns are ignored and counted), total and annualized return, annualized volatility, Sharpe, Sortino,
Calmar, and Omega ratios, maximum and average drawdown, ulcer index, expected
shortfall, skewness, excess kurtosis, annualized downside volatility, best and
worst period returns, positive-period rate, maximum drawdown duration, and time
in drawdown. Metrics that cannot be estimated, such as volatility from one
observation or a ratio with a zero denominator, are `nothing`.

`PerformanceConfig(periods_per_year; annual_risk_free_rate, annual_minimum_acceptable_return,
expected_shortfall_probability, drawdown_method)` defaults to 252 periods per
year, zero reference rates, a 5% expected-shortfall tail, and `:compounded`
drawdowns. Annual rates are simple rates divided by `periods_per_year` before
they are used as periodic Sharpe, Sortino, downside-volatility, and Omega
thresholds. For monthly returns use `PerformanceConfig(12; annual_risk_free_rate=0.03)`.

```@example analytics
using Fastback
using Dates
using DataFrames

performance_summary([0.01, -0.004, 0.007, 0.002], PerformanceConfig(252))
```

`account_performance_summary(acc, returns, config)` and
`account_performance_summary_from_equity(acc, equity, config)` return an
`AccountPerformanceSummary`: the performance summary plus applied trade count,
closing trade count, and winner/loser rates of recorded closing trades
(`nothing` when trade history is not tracked):

```julia
account_performance_summary_from_equity(acc, equity_data, PerformanceConfig(252))
```

`performance_summary_table` returns either summary as a one-row Tables.jl
source with undefined metrics as `missing`. Convert it to a `DataFrame` when that
is convenient:

```julia
DataFrame(performance_summary_table(performance_summary_from_equity(equity_data, PerformanceConfig(252))))
```

For an equity collector:

```julia
collect_equity, equity_data = periodic_collector(Float64, Day(1))
collect_equity(DateTime(2026, 1, 1), 10_000.0)
collect_equity(DateTime(2026, 1, 2), 10_100.0)
collect_equity(DateTime(2026, 1, 3), 10_050.0)

performance_summary_from_equity(equity_data, PerformanceConfig(252))
```

## Trade Diagnostics

The trade diagnostics operate on `acc.trades` or on any vector of `Trade`s.
`trade_summary` groups monetary fields by currency: quote-currency summaries
carry return diagnostics, while settlement-currency summaries carry settlement
cash P&L and commissions.

```@example analytics
acc = Account(;
    funding=AccountFunding.Margined,
    base_currency=CashSpec(:USD),
    broker=FlatFeeBroker(fixed=1.0),
)
deposit!(acc, :USD, 10_000.0)

inst = register_instrument!(acc, spot_instrument(Symbol("ABC/USD"), :ABC, :USD))

dt0 = DateTime(2026, 1, 1)
fill_order!(
    acc,
    create_order!(acc, inst, dt0, 100.0, 2.0);
    dt=dt0,
    fill_price=100.0,
    bid=100.0,
    ask=100.0,
    last=100.0,
)

win_trade = fill_order!(
    acc,
    create_order!(acc, inst, dt0 + Day(1), 110.0, -1.0);
    dt=dt0 + Day(1),
    fill_price=110.0,
    bid=110.0,
    ask=110.0,
    last=110.0,
)

loss_trade = fill_order!(
    acc,
    create_order!(acc, inst, dt0 + Day(2), 90.0, -1.0);
    dt=dt0 + Day(2),
    fill_price=90.0,
    bid=90.0,
    ask=90.0,
    last=90.0,
)

trade_summary(acc)
```

The quote-currency P&L helpers are direct companions to the realized return
helpers:

```@example analytics
(
    gross_pnl_quote=gross_realized_pnl_quote(win_trade),
    net_pnl_quote=net_realized_pnl_quote(win_trade),
    net_return=realized_return_net(win_trade),
)
```

These helpers report quote-currency P&L. They are useful for trade diagnostics,
but they are not a replacement for `t.fill_pnl_settle` when settlement currency
or point-in-time FX conversion matters.

## Holding Periods

`realized_holding_periods` reconstructs FIFO lots by instrument symbol from the
trade stream. Ordinary open/close trades and partial exits are exact under FIFO.
Scale-in, reduce, and flip cases are FIFO approximations because Fastback stores
one netted position per instrument, not full lot identity.

```@example analytics
realized_holding_periods(acc)
```

```@example analytics
holding_period_summary(acc)
```

When the reconstructed lots disagree with a trade's pre-fill position, for
example because the trade vector starts after the position opened, that exposure
has an unknown entry and its realization records no period. A lot that matches
the remaining realized quantity within rounding noise closes completely, so
floating-point residue never appears as a separate holding period.

## P&L Concentration

`pnl_concentration` returns a Tables.jl-compatible table and always groups
internally by `(bucket, quote_symbol)` so quote currencies are not silently
summed together. Share columns are normalized within each quote currency.

```@example analytics
DataFrame(pnl_concentration(acc; by=:trade))
```

You can also group by instrument or by calendar period:

```@example analytics
DataFrame(pnl_concentration(acc; by=:instrument))
```

```@example analytics
DataFrame(pnl_concentration(acc; by=:period, period=:month))
```

Supported `by` values are `:instrument`, `:period`, and `:trade`. Supported
period buckets are `:day`, `:month`, and `:year`. Period grouping requires
date-bearing timestamps; `Dates.Time`-only trade streams can use `:instrument`
or `:trade` grouping.
