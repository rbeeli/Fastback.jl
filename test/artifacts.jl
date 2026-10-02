using TestItemRunner

@testitem "standard report writes Markdown, Parquet exports, and charts" begin
    using Test, Fastback, Dates, Parquet2, Tables
    using Fastback.Artifacts

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("ART/USD"), :ART, :USD))
    start = DateTime(2030, 1, 1, 21)
    fill_order!(acc, Order(oid!(acc), inst, start, 100.0, 10.0); dt=start, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    portfolio = Portfolio(acc)
    recorder = ReportRecorder()
    benchmark = CausalBuyAndHoldBenchmark("Benchmark", 10_000.0)
    for (day, price) in enumerate((100.0, 102.0, 101.0, 105.0))
        timestamp = start + Day(day - 1)
        update_marks!(acc, inst, timestamp, price, price, price)
        record!(recorder, ReportObservation(portfolio, timestamp, observe!(benchmark, timestamp, price)))
    end
    directory = mktempdir()
    spec = StandardReportSpec("Artifact test", directory, PerformanceConfig(252.0); additional_cost_stress_basis_points=[5.0])
    report = standard_backtest_report(acc, finish(recorder), spec)
    paths = write_with_markdown_appendix(report, "## Appendix\n")
    markdown = read(paths.report, String)
    @test startswith(markdown, "# Artifact test\n\n## Scope\n\n- Period: 2030-01-01 21:00:00 UTC through 2030-01-04 21:00:00 UTC")
    @test occursin("## Benchmark Performance", markdown)
    @test occursin("## Additional cost stress", markdown)
    @test endswith(markdown, "## Appendix\n")
    observations = Tables.columntable(Parquet2.Dataset(paths.observations))
    @test length(observations.timestamp) == 4
    @test observations.strategy_equity[end] ≈ 10_050.0
    @test Tables.columnnames(Parquet2.Dataset(paths.trades)) == (:trade_id, :timestamp, :symbol, :fill_price,
        :fill_quantity, :notional_base, :commission_settlement, :realized_quantity)
    @test occursin("width=\"1200\" height=\"680\"", read(paths.equity_chart, String))
    @test occursin("width=\"1200\" height=\"340\"", read(paths.turnover_chart, String))
    @test carry(benchmark, start + Day(5)) == benchmark.equity
    @test_throws ArgumentError observe!(benchmark, start, 100.0)
end

@testitem "diagnostics and normalized comparisons validate and write their artifacts" begin
    using Test, Fastback, Dates, Parquet2, Tables
    using Fastback.Artifacts

    timestamps = [DateTime(2030, 1, day) for day in 1:3]
    directory = mktempdir()
    series = [DiagnosticSeries("first", [1.0, 2.0, 3.0]), DiagnosticSeries("second", [2.0, 2.0, 1.0])]
    write(DiagnosticTimeSeries(timestamps, series), joinpath(directory, "diag.parquet"), joinpath(directory, "diag.svg"),
        "Diagnostics", "value")
    @test Tables.columnnames(Parquet2.Dataset(joinpath(directory, "diag.parquet"))) == (:timestamp, :first, :second)
    @test isfile(joinpath(directory, "diag.svg"))
    write_normalized_performance_comparison(joinpath(directory, "cmp.svg"), joinpath(directory, "cmp.parquet"), timestamps,
        series, "Comparison")
    comparison = Tables.columntable(Parquet2.Dataset(joinpath(directory, "cmp.parquet")))
    @test comparison.strategy_id == ["first", "second", "first", "second", "first", "second"]
    @test occursin("normalized level (log scale)", read(joinpath(directory, "cmp.svg"), String))
    @test_throws ArgumentError DiagnosticSeries("timestamp", [1.0])
    @test_throws ArgumentError DiagnosticSeries("x", [NaN])
    @test_throws ArgumentError DiagnosticTimeSeries(timestamps, [DiagnosticSeries("x$(index)", ones(3)) for index in 1:5])
    @test_throws ArgumentError write_diagnostic_parquet(joinpath(directory, "bad.parquet"), reverse(timestamps), series)
end
