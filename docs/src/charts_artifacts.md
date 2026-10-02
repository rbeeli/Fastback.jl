# Charts and standard artifacts

`Fastback.Charts` renders standalone, self-contained SVG charts without loading fonts or plotting
packages: line, scatter, categorical bar, and stacked interval bar charts with numeric or temporal
x values and up to two independent vertical axes. Axis sides, scales, and tick formats are symbols
(`:left`/`:right`, `:linear`/`:logarithmic`, `:number`/`:percentage`); a legend is a positive
column count, or `nothing` to hide it.

```julia
using Fastback, Dates
using Fastback.Charts

times = [DateTime(2030, 1, day) for day in 1:5]
equity = [100.0, 102.0, 101.0, 105.0, 107.0]
write_svg_line_chart("equity.svg", [LineSeries("strategy", times, equity)],
    ChartOptions(; width=1200, height=680, title="Equity",
        left_y_axis=AxisOptions(; label="base currency", scale=:logarithmic)))
```

`Fastback.Artifacts` builds the standard backtest report from period-end `ReportObservation`s and
an account's retained trades: `RESULTS.md`-style Markdown, observation and trade Parquet exports,
and equity, normalized-performance, exposure, and turnover charts. It also writes auxiliary
diagnostic tables and charts (`DiagnosticTimeSeries`, `write_diagnostic_parquet`,
`write_typed_diagnostic_parquet`), normalized performance comparisons, and tracks a
`CausalBuyAndHoldBenchmark`. Parquet output requires the Parquet2 extension:

```julia
using Fastback, Parquet2
using Fastback.Artifacts

recorder = ReportRecorder()
# record!(recorder, ReportObservation(portfolio, timestamp, benchmark_equity)) at each period end
spec = StandardReportSpec("My strategy", abspath("results"), PerformanceConfig(252.0))
report = standard_backtest_report(portfolio.account, finish(recorder), spec)
write(report)
```

Equal inputs produce the same documents as the Rust `fastback` crate's `plots` and `artifacts`
modules.
