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

@testitem "streamed report inputs reproduce the retained-trade report" begin
    using Test, Fastback, Dates, Parquet2, Tables
    using Fastback.Artifacts

    directory = mktempdir()
    retained = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=FlatFeeBroker(; pct=0.001))
    recorder = ReportRecorder()
    analytics = TradeAnalytics{DateTime}()
    sink = TradeParquetSink(joinpath(directory, "streamed_trades.parquet"); batch_rows=2)
    streamed = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=FlatFeeBroker(; pct=0.001),
        track_trades=false, trade_sink=TradeSinks(recorder, analytics, sink))
    accounts = (retained, streamed)
    instruments = map(accounts) do acc
        deposit!(acc, :USD, 10_000.0)
        (register_instrument!(acc, spot_instrument(Symbol("A/USD"), :A, :USD)),
            register_instrument!(acc, spot_instrument(Symbol("B/USD"), :B, :USD)))
    end
    start = DateTime(2030, 1, 1, 21)
    # Quantities per day and instrument: opens, a partial exit, a flip and a close; the second fill of a day
    # lands on the observation's timestamp after the observation.
    fills = [(1, 10.0, 0.0), (2, -4.0, 5.0), (3, -10.0, -5.0), (4, 4.0, 0.0), (5, 0.0, 0.0)]
    retained_observations = ReportObservation[]
    for (day, quantity_a, quantity_b) in fills
        timestamp = start + Day(day - 1)
        prices = (100.0 + day, 50.0 - day)
        for (index, acc) in enumerate(accounts)
            a, b = instruments[index]
            update_marks!(acc, a, timestamp, prices[1], prices[1], prices[1])
            update_marks!(acc, b, timestamp, prices[2], prices[2], prices[2])
            quantity_a == 0.0 || fill_order!(acc, Order(oid!(acc), a, timestamp, prices[1], quantity_a); dt=timestamp,
                fill_price=prices[1], bid=prices[1], ask=prices[1], last=prices[1])
            observation = ReportObservation(Portfolio(acc), timestamp, nothing)
            index == 1 ? push!(retained_observations, observation) : record!(recorder, observation)
            quantity_b == 0.0 || fill_order!(acc, Order(oid!(acc), b, timestamp, prices[2], quantity_b); dt=timestamp,
                fill_price=prices[2], bid=prices[2], ask=prices[2], last=prices[2])
        end
    end
    close(sink)
    @test isempty(streamed.trades) && streamed.trade_count == retained.trade_count == sink.count
    spec = StandardReportSpec("Streamed", directory, PerformanceConfig(252.0); additional_cost_stress_basis_points=[5.0])
    expected = standard_backtest_report(retained, retained_observations, spec)
    inputs = report_inputs(recorder, analytics, streamed.trade_count, sink.count)
    actual = standard_backtest_report(inputs, spec)
    @test render_markdown(actual) == render_markdown(expected)
    @test actual.turnover == expected.turnover
    @test inputs.gross_traded[2] > abs(4.0 * 102.0)  # includes the fill on the observation timestamp
    expected_trades = joinpath(directory, "retained_trades.parquet")
    Artifacts.write_parquet_table(expected_trades, Artifacts._trade_columns(retained.trades))
    @test Tables.columntable(Parquet2.Dataset(sink.path)) == Tables.columntable(Parquet2.Dataset(expected_trades))
    @test trade_summary(analytics).quote_summaries == trade_summary(retained).quote_summaries
    @test holding_period_summary(analytics) == holding_period_summary(retained)
    @test pnl_concentration(analytics).net_realized_pnl_quote == pnl_concentration(retained).net_realized_pnl_quote
end
