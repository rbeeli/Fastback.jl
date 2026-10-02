"""
Standard backtest artifacts: period-end report observations, the standard Markdown report with its
Parquet exports and SVG charts, auxiliary diagnostic tables and charts, causal buy-and-hold
benchmarks, and normalized performance comparisons.

Parquet output requires the Parquet2 package: `using Parquet2` loads the writer extension.
Timestamps are `DateTime` values interpreted as UTC.
"""
module Artifacts

using Dates
using Printf

import ..Fastback
using ..Fastback: PerformanceConfig, PerformanceSummary, _finite_option, performance_summary
using ..Charts:
    AxisOptions, ChartOptions, DARK_PLOT_THEME, LineSeries, write_svg_line_chart

export AdditionalCostStressRow,
    CausalBuyAndHoldBenchmark,
    DiagnosticSeries,
    DiagnosticTimeSeries,
    ReportObservation,
    ReportPeriodReturn,
    ReportRecorder,
    StandardBacktestReport,
    StandardReportOutputPaths,
    StandardReportSpec,
    carry,
    finish,
    markdown_artifact_link,
    observe!,
    record!,
    render_markdown,
    report_period_returns,
    standard_backtest_report,
    write_diagnostic_parquet,
    write_normalized_performance_comparison,
    write_normalized_performance_comparison_with_y_axis_scale,
    write_performance_charts,
    write_typed_diagnostic_parquet,
    write_with_markdown_appendix

const CHART_Y_SCALES = (:linear, :logarithmic)
const SERIES_PALETTE = DARK_PLOT_THEME.series_palette
const CHART_PRIMARY = SERIES_PALETTE[1]
const CHART_SECONDARY = SERIES_PALETTE[2]
const CHART_NEGATIVE = SERIES_PALETTE[3]
const CHART_CASH = SERIES_PALETTE[5]

"""
    write_parquet_table(path, columns::NamedTuple)

Atomically write equal-length columns as one Snappy-compressed Parquet table. Implemented by the
Parquet2 extension.
"""
function write_parquet_table end

function _write_parquet(path::AbstractString, columns::NamedTuple)
    hasmethod(write_parquet_table, Tuple{String,typeof(columns)}) ||
        throw(ArgumentError("Writing '$(path)' requires the Parquet2 extension; load it with `using Parquet2`."))
    mkpath(dirname(path))
    write_parquet_table(String(path), columns)
    return nothing
end

"""Report text of a UTC timestamp, with milliseconds only when present."""
function display_timestamp(timestamp::DateTime)::String
    millisecond(timestamp) == 0 && return Dates.format(timestamp, dateformat"yyyy-mm-dd HH:MM:SS") * " UTC"
    return Dates.format(timestamp, dateformat"yyyy-mm-dd HH:MM:SS.sss") * " UTC"
end

# Report observations

"""One period-end valuation of the evaluation account and its optional benchmark."""
struct ReportObservation
    timestamp::DateTime
    equity::Float64
    benchmark_equity::Union{Nothing,Float64}
    gross_exposure::Float64
    net_exposure::Float64
    cash_weight::Float64

    function ReportObservation(timestamp::DateTime, equity::Real, benchmark_equity, gross_exposure::Real,
        net_exposure::Real, cash_weight::Real)
        isfinite(equity) && equity > 0 || throw(ArgumentError("Equity must be positive and finite at $(timestamp)."))
        isnothing(benchmark_equity) || (isfinite(benchmark_equity) && benchmark_equity > 0) ||
            throw(ArgumentError("Benchmark equity must be positive and finite at $(timestamp)."))
        isfinite(gross_exposure) && gross_exposure >= 0 && isfinite(net_exposure) && isfinite(cash_weight) ||
            throw(ArgumentError("Exposure and cash weight must be finite, with nonnegative gross exposure at $(timestamp)."))
        return new(timestamp, equity, isnothing(benchmark_equity) ? nothing : Float64(benchmark_equity),
            gross_exposure, net_exposure, cash_weight)
    end
end

"""The observation of a portfolio's account at `timestamp`, with an optional benchmark level."""
function ReportObservation(portfolio::Fastback.Portfolio, timestamp::DateTime, benchmark_equity)
    exposure = Fastback.portfolio_exposure(portfolio)
    equity = exposure.snapshot.equity
    isfinite(equity) && equity > 0 || throw(ArgumentError("Account weights require positive finite equity."))
    return ReportObservation(timestamp, equity, benchmark_equity, exposure.gross_notional / equity,
        exposure.net_notional / equity, exposure.snapshot.balance / equity)
end

"""Records period observations in strictly increasing time, with a benchmark for all or none."""
mutable struct ReportRecorder
    observations::Vector{ReportObservation}
end

ReportRecorder() = ReportRecorder(ReportObservation[])

function record!(recorder::ReportRecorder, observation::ReportObservation)::Nothing
    if !isempty(recorder.observations)
        previous = last(recorder.observations)
        observation.timestamp > previous.timestamp ||
            throw(ArgumentError("Report timestamp $(observation.timestamp) must follow $(previous.timestamp)."))
        isnothing(observation.benchmark_equity) == isnothing(previous.benchmark_equity) ||
            throw(ArgumentError("Benchmark equity must be present for every observation or none."))
    end
    push!(recorder.observations, observation)
    return nothing
end

function finish(recorder::ReportRecorder)::Vector{ReportObservation}
    isempty(recorder.observations) && throw(ArgumentError("Standard report requires at least one observation."))
    return recorder.observations
end

"""Strategy and benchmark returns of one period, timed at its end."""
struct ReportPeriodReturn
    timestamp::DateTime
    strategy_return::Float64
    benchmark_return::Union{Nothing,Float64}
end

function _validated_simple_return(previous::Float64, current::Float64, label::AbstractString, timestamp::DateTime)
    value = current / previous - 1.0
    isfinite(value) && value > -1.0 ||
        throw(ArgumentError("$(label) levels $(previous) and $(current) produce invalid simple return $(value) at $(timestamp)."))
    return value
end

"""The simple returns between consecutive observations."""
function report_period_returns(observations::AbstractVector{ReportObservation})::Vector{ReportPeriodReturn}
    isempty(observations) && throw(ArgumentError("Standard report requires at least one observation."))
    return [ReportPeriodReturn(observations[i].timestamp,
        _validated_simple_return(observations[i - 1].equity, observations[i].equity, "strategy equity", observations[i].timestamp),
        isnothing(observations[i].benchmark_equity) ? nothing :
        _validated_simple_return(something(observations[i - 1].benchmark_equity), something(observations[i].benchmark_equity),
            "benchmark equity", observations[i].timestamp)) for i in 2:length(observations)]
end

# Standard report

"""
The title, destinations, metrics configuration, and options of one standard report.
`performance_y_axis_scale` is `:linear` or `:logarithmic`.
"""
struct StandardReportSpec
    title::String
    output_directory::String
    report_path::String
    performance_export_path::String
    trades_export_path::String
    performance::PerformanceConfig
    benchmark_label::String
    additional_cost_stress_basis_points::Vector{Float64}
    performance_y_axis_scale::Symbol
end

function StandardReportSpec(title::AbstractString, output_directory::AbstractString, performance::PerformanceConfig;
    report_path::AbstractString=joinpath(output_directory, "RESULTS.md"),
    performance_export_path::AbstractString=joinpath(output_directory, "observations.parquet"),
    trades_export_path::AbstractString=joinpath(output_directory, "trades.parquet"),
    benchmark_label::AbstractString="Benchmark", additional_cost_stress_basis_points=Float64[],
    performance_y_axis_scale::Symbol=:logarithmic)
    !isempty(title) && strip(title) == title ||
        throw(ArgumentError("Report title must be nonempty without surrounding whitespace."))
    isabspath(output_directory) || throw(ArgumentError("Report output directory '$(output_directory)' must be absolute."))
    !isempty(benchmark_label) && strip(benchmark_label) == benchmark_label ||
        throw(ArgumentError("Benchmark label must be nonempty without surrounding whitespace."))
    stresses = collect(Float64, additional_cost_stress_basis_points)
    all(value -> isfinite(value) && value >= 0, stresses) && issorted(stresses; lt=<=) || isempty(stresses) ||
        throw(ArgumentError("Additional cost stresses must be nonnegative, finite, and strictly increasing."))
    performance_y_axis_scale in CHART_Y_SCALES ||
        throw(ArgumentError("Chart y-axis scale must be :linear or :logarithmic; received $(repr(performance_y_axis_scale))."))
    mkpath(output_directory)
    return StandardReportSpec(String(title), String(output_directory), String(report_path), String(performance_export_path),
        String(trades_export_path), performance, String(benchmark_label), stresses, performance_y_axis_scale)
end

"""The artifact paths a standard report writes."""
struct StandardReportOutputPaths
    report::String
    observations::String
    trades::String
    equity_chart::String
    normalized_chart::String
    exposure_chart::String
    turnover_chart::String
end

StandardReportOutputPaths(directory::AbstractString, report::AbstractString, observations::AbstractString,
    trades::AbstractString) =
    StandardReportOutputPaths(String(report), String(observations), String(trades),
        joinpath(directory, "equity.svg"), joinpath(directory, "normalized.svg"), joinpath(directory, "exposure.svg"),
        joinpath(directory, "turnover.svg"))

"""Performance of the strategy returns after an additional cost on gross traded notional."""
struct AdditionalCostStressRow
    basis_points::Float64
    performance::PerformanceSummary
end

"""A complete standard report of one evaluation account."""
struct StandardBacktestReport
    spec::StandardReportSpec
    paths::StandardReportOutputPaths
    observations::Vector{ReportObservation}
    period_returns::Vector{ReportPeriodReturn}
    drawdowns::Vector{Float64}
    turnover::Vector{Float64}
    performance::PerformanceSummary
    applied_trade_count::Int
    closing_trade_count::Int
    winner_rate::Union{Nothing,Float64}
    loser_rate::Union{Nothing,Float64}
    benchmark_performance::Union{Nothing,PerformanceSummary}
    additional_cost_stress::Vector{AdditionalCostStressRow}
    trade_summary::Any
    holding_periods::Any
    pnl_concentration::Any
    trades::Vector{Any}
end

"""Benchmark drawdowns: `equity / peak - 1` at each observation."""
function _drawdown_fractions(equity::AbstractVector{Float64})::Vector{Float64}
    peak = -Inf
    return [begin
        peak = max(peak, value)
        value / peak - 1.0
    end for value in equity]
end

"""Strategy drawdowns as the percentage drawdown collector records them: `min(equity - peak, 0) / peak`."""
function _strategy_drawdown_fractions(equity::AbstractVector{Float64})::Vector{Float64}
    peak = -Inf
    return [begin
        peak = max(peak, value)
        min(value - peak, 0.0) / peak
    end for value in equity]
end

"""
    standard_backtest_report(account, observations, spec) -> StandardBacktestReport

Build the report of an account from its period observations and retained trades.
"""
function standard_backtest_report(account::Fastback.Account, observations::AbstractVector{ReportObservation},
    spec::StandardReportSpec)::StandardBacktestReport
    period_returns = report_period_returns(observations)
    paths = StandardReportOutputPaths(spec.output_directory, spec.report_path, spec.performance_export_path,
        spec.trades_export_path)
    trades = account.trades
    gross_traded = zeros(length(observations))
    trade_index = 1
    for (index, observation) in pairs(observations)
        while trade_index <= length(trades) && trades[trade_index].date <= observation.timestamp
            gross_traded[index] += abs(trades[trade_index].notional_base)
            trade_index += 1
        end
    end
    trade_index > length(trades) || throw(ArgumentError("Retained trades extend beyond the final report observation."))
    turnover = [gross / (2.0 * observation.equity) for (gross, observation) in zip(gross_traded, observations)]
    equity = [observation.equity for observation in observations]
    performance = performance_summary([period.strategy_return for period in period_returns], spec.performance)
    closing = [trade for trade in trades if Fastback.is_realizing(trade)]
    realized = [Fastback.realized_return_net(trade) for trade in closing]
    winner_rate = isempty(closing) ? nothing : count(>(0.0), realized) / length(closing)
    loser_rate = isempty(closing) ? nothing : count(<(0.0), realized) / length(closing)
    benchmark_performance = isnothing(first(observations).benchmark_equity) ? nothing :
        performance_summary([something(period.benchmark_return) for period in period_returns], spec.performance)
    stresses = map(spec.additional_cost_stress_basis_points) do basis_points
        returns = map(eachindex(period_returns)) do index
            stressed = period_returns[index].strategy_return -
                basis_points / 10_000.0 * gross_traded[index + 1] / observations[index].equity
            isfinite(stressed) && stressed > -1.0 || throw(ArgumentError(
                "Additional cost stress of $(basis_points) bps produces invalid return $(stressed) at $(period_returns[index].timestamp).",
            ))
            stressed
        end
        AdditionalCostStressRow(basis_points, performance_summary(returns, spec.performance))
    end
    return StandardBacktestReport(spec, paths, collect(observations), period_returns, _strategy_drawdown_fractions(equity), turnover,
        performance, account.trade_count, length(closing), winner_rate, loser_rate, benchmark_performance, stresses,
        Fastback.trade_summary(trades), Fastback.holding_period_summary(trades), Fastback.pnl_concentration(trades; by=:instrument),
        collect(Any, trades))
end

_format_optional(value::Union{Nothing,Float64}, percent::Bool) =
    isnothing(value) ? "n/a" : percent ? @sprintf("%.4f", value * 100.0) : @sprintf("%.6f", value)
_format_percentage(value) = value isa Real && isfinite(value) ? @sprintf("%.4f%%", value * 100.0) : "n/a"

function _format_period(value)
    (ismissing(value) || isnothing(value)) && return "n/a"
    seconds = Dates.value(Millisecond(value)) / 1_000
    seconds >= 86_400 && return @sprintf("%.4f days", seconds / 86_400)
    seconds >= 3_600 && return @sprintf("%.4f hours", seconds / 3_600)
    return @sprintf("%.4f seconds", seconds)
end

_metric_row(name, value, percent, unit) = "| $(name) | $(_format_optional(value, percent)) | $(unit) |\n"
_count_row(name, value, unit) = "| $(name) | $(value) | $(unit) |\n"

function _path_metrics(summary::PerformanceSummary)
    negative(value) = isnothing(value) ? nothing : -abs(value)
    rows = [
        ("Total return", summary.total_return, true, "pct"), ("Annualized return", summary.annualized_return, true, "pct"),
        ("Annualized volatility", summary.annualized_volatility, true, "pct"), ("Sharpe ratio", summary.sharpe_ratio, false, "ratio"),
        ("Sortino ratio", summary.sortino_ratio, false, "ratio"),
        ("Maximum drawdown", negative(summary.maximum_drawdown), true, "pct"),
        ("Average drawdown", negative(summary.average_drawdown), true, "pct"), ("Ulcer index", summary.ulcer_index, true, "pct"),
        ("Calmar ratio", summary.calmar_ratio, false, "ratio"), ("Omega ratio", summary.omega_ratio, false, "ratio"),
        ("Expected shortfall", summary.expected_shortfall, true, "pct"), ("Skewness", summary.skewness, false, "ratio"),
        ("Excess kurtosis", summary.excess_kurtosis, false, "ratio"),
        ("Annualized downside volatility", summary.annualized_downside_volatility, true, "pct"),
        ("Best period return", summary.best_return, true, "pct"), ("Worst period return", summary.worst_return, true, "pct"),
        ("Positive period rate", summary.positive_period_rate, true, "pct"),
        ("Time in drawdown", summary.time_in_drawdown_rate, true, "pct"),
    ]
    return join(_metric_row(row...) for row in rows)
end

"""The relative path from the report's directory to an artifact."""
markdown_artifact_link(report::AbstractString, artifact::AbstractString) = relpath(artifact, dirname(report))

"""The standard Markdown report."""
function render_markdown(report::StandardBacktestReport)::String
    first_observation, last_observation = first(report.observations), last(report.observations)
    summary = report.trade_summary
    io = IOBuffer()
    print(io, "# $(report.spec.title)\n\n## Scope\n\n- Period: $(display_timestamp(first_observation.timestamp)) through ",
        "$(display_timestamp(last_observation.timestamp))\n- Period observations: $(length(report.observations))\n",
        "- Applied fills: $(report.applied_trade_count)\n- Retained fills: $(length(report.trades))\n",
        @sprintf("- Annualization: %.4f periods/year\n\n", report.spec.performance.periods_per_year))
    performance = report.performance
    print(io, "## Strategy Performance\n\n| Metric | Value | Unit |\n|---|---:|---|\n",
        _count_row("Return observations", performance.observations, "count"),
        _count_row("Ignored return observations", performance.ignored_observations, "count"), _path_metrics(performance),
        _count_row("Maximum drawdown duration", performance.maximum_drawdown_duration, "periods"),
        _count_row("Applied fills", report.applied_trade_count, "count"), _count_row("Closing fills", report.closing_trade_count, "count"),
        _metric_row("Winning closing-fill rate", report.winner_rate, true, "pct"),
        _metric_row("Losing closing-fill rate", report.loser_rate, true, "pct"),
        _metric_row("Average round-trip turnover", isempty(report.turnover) ? nothing : sum(report.turnover) / length(report.turnover),
            false, "equity fraction"),
        _metric_row("Total round-trip turnover", sum(report.turnover), false, "equity fraction"),
        _count_row("Turnover observations", length(report.turnover), "count"))
    if !isnothing(report.benchmark_performance)
        benchmark = something(report.benchmark_performance)
        print(io, "\n## $(report.spec.benchmark_label) Performance\n\n| Metric | Value | Unit |\n|---|---:|---|\n",
            _count_row("Return observations", benchmark.observations, "count"), _path_metrics(benchmark))
    end
    print(io, "\n## Calendar-year stability\n\n| Year | Return observations | Total return | Annualized return | ",
        "Volatility | Sharpe | Maximum drawdown |\n|---|---:|---:|---:|---:|---:|---:|\n")
    years = sort!(unique(year(period.timestamp) for period in report.period_returns))
    for calendar_year in years
        yearly = performance_summary([period.strategy_return for period in report.period_returns
            if year(period.timestamp) == calendar_year], report.spec.performance)
        drawdown = isnothing(yearly.maximum_drawdown) ? nothing : -abs(something(yearly.maximum_drawdown))
        print(io, "| $(calendar_year) | $(yearly.observations) | $(_format_optional(yearly.total_return, true)) | ",
            "$(_format_optional(yearly.annualized_return, true)) | $(_format_optional(yearly.annualized_volatility, true)) | ",
            "$(_format_optional(yearly.sharpe_ratio, false)) | $(_format_optional(drawdown, true)) |\n")
    end
    print(io, "\n")
    holding = report.holding_periods
    print(io, "\n## Trade diagnostics\n\n- Realizing fills: $(summary.realized_trade_count)\n",
        "- Finite realized returns: $(summary.finite_realized_count)\n- Hit rate: $(_format_percentage(summary.hit_rate))\n",
        "- Realized FIFO lots: $(holding.realized_lot_count)\n- Average holding period: $(_format_period(holding.average_holding_period))\n",
        "- Median holding period: $(_format_period(holding.median_holding_period))\n\n")
    if !isempty(summary.quote_summaries)
        print(io, "| Quote currency | Fills | Realizing fills | Commission | Gross realized PnL | Net realized PnL | Hit rate | ",
            "Average win | Average loss | Payoff asymmetry |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n")
        for currency in summary.quote_summaries
            print(io, @sprintf("| %s | %d | %d | %.6f | %.6f | %.6f | %s | %s | %s | %s |\n", currency.symbol,
                currency.trade_count, currency.realized_trade_count, currency.total_commission,
                currency.gross_realized_pnl_quote, currency.net_realized_pnl_quote, _format_percentage(currency.hit_rate),
                _format_optional(_finite_option(currency.average_win_quote), false),
                _format_optional(_finite_option(currency.average_loss_quote), false),
                _format_optional(_finite_option(currency.payoff_asymmetry), false)))
        end
        print(io, "\n")
    end
    if !isempty(report.additional_cost_stress)
        print(io, "\n## Additional cost stress\n\n| Additional cost (bps) | Total return | Annualized return | Sharpe | ",
            "Maximum drawdown |\n|---:|---:|---:|---:|---:|\n")
        for row in report.additional_cost_stress
            drawdown = isnothing(row.performance.maximum_drawdown) ? nothing : -abs(something(row.performance.maximum_drawdown))
            print(io, @sprintf("| %.4f | %s | %s | %s | %s |\n", row.basis_points,
                _format_optional(row.performance.total_return, true), _format_optional(row.performance.annualized_return, true),
                _format_optional(row.performance.sharpe_ratio, false), _format_optional(drawdown, true)))
        end
        print(io, "\nStress charges are incremental to the modeled account path and are applied to gross traded notional ",
            "without rerunning quantity selection.\n")
    end
    concentration = report.pnl_concentration
    if !isempty(concentration.bucket)
        print(io, "\n## Realized PnL concentration\n\n| Instrument | Quote currency | Realizing fills | Gross realized PnL | ",
            "Net realized PnL | Share of absolute PnL |\n|---|---|---:|---:|---:|---:|\n")
        for index in eachindex(concentration.bucket)
            print(io, @sprintf("| %s | %s | %d | %.6f | %.6f | %s |\n", concentration.bucket[index],
                concentration.quote_symbol[index], concentration.realized_trade_count[index],
                concentration.gross_realized_pnl_quote[index], concentration.net_realized_pnl_quote[index],
                _format_percentage(concentration.share_of_abs_pnl[index])))
        end
        print(io, "\n")
    end
    link(path) = markdown_artifact_link(report.paths.report, path)
    print(io, "## Diagnostics\n\n![Strategy equity and drawdown]($(link(report.paths.equity_chart)))\n\n",
        "![Normalized strategy and benchmark with strategy drawdown]($(link(report.paths.normalized_chart)))\n\n",
        "![Exposure]($(link(report.paths.exposure_chart)))\n\n![Turnover]($(link(report.paths.turnover_chart)))\n\n",
        "## Artifacts\n\n- [$(basename(report.paths.observations))]($(link(report.paths.observations))): period equity, ",
        "benchmark, exposure, turnover, and drawdown\n- [$(basename(report.paths.trades))]($(link(report.paths.trades))): ",
        "retained fill-level execution evidence\n\n",
        "## Integrity notes\n\nMetrics use period-end equity and retained account history. Undefined metrics are reported as ",
        "`n/a`; non-finite observations are rejected before artifact creation. Exposure and turnover diagnostics verify that ",
        "modeled risk changes reached the account path, but do not by themselves validate the economic mechanism.\n")
    return String(take!(io))
end

# Standard charts

struct ChartLayout
    size::Tuple{Int,Int}
    legend::Union{Nothing,Int}
    emphasize_last::Bool
    drawdowns::Union{Nothing,Vector{Float64}}
end

const STANDARD_CHART_LAYOUT = ChartLayout((1_200, 680), 4, false, nothing)
const COMPACT_CHART_LAYOUT = ChartLayout((1_200, 340), 4, false, nothing)
const COMPACT_CHART_LAYOUT_WITHOUT_LEGEND = ChartLayout((1_200, 340), nothing, false, nothing)

_performance_y_axis_label(label::AbstractString, scale::Symbol) = scale == :linear ? String(label) : "$(label) (log scale)"

function _validate_chart_path(path::AbstractString)
    !isempty(basename(path)) && endswith(path, ".svg") ||
        throw(ArgumentError("Chart path '$(path)' must use a .svg extension."))
    return nothing
end

function _prepare_report_path(path::AbstractString)
    isabspath(path) && !isempty(basename(path)) ||
        throw(ArgumentError("Report path '$(path)' must be absolute with a file name."))
    mkpath(dirname(path))
    return nothing
end

function _write_chart(path::AbstractString, title::AbstractString, y_label::AbstractString, timestamps::AbstractVector{DateTime},
    series, y_scale::Symbol, layout::ChartLayout)
    !isempty(timestamps) && all(index -> timestamps[index - 1] < timestamps[index], 2:length(timestamps)) &&
        all(item -> all(isfinite, item[2]), series) ||
        throw(ArgumentError("Report charts require finite values and ordered timestamps."))
    lines = LineSeries[LineSeries(name, timestamps, values; color,
        width=layout.emphasize_last && index == length(series) ? 2.0 : 1.2) for (index, (name, values, color)) in enumerate(series)]
    if !isnothing(layout.drawdowns)
        drawdowns = something(layout.drawdowns)
        length(drawdowns) == length(timestamps) && all(value -> isfinite(value) && -1.0 <= value <= 0.0, drawdowns) ||
            throw(ArgumentError("Strategy drawdowns require one finite fraction in [-1, 0] per timestamp."))
        push!(lines, LineSeries("strategy drawdown", timestamps, drawdowns; axis=:right, color="rgba(255, 0, 255, 0.5)"))
    end
    options = ChartOptions(; width=layout.size[1], height=layout.size[2], title=String(title),
        left_y_axis=AxisOptions(; label=String(y_label), scale=y_scale == :logarithmic ? :logarithmic : :linear),
        right_y_axis=isnothing(layout.drawdowns) ? nothing :
                     AxisOptions(; label="strategy drawdown", limits=(-1.0, 0.0), format=:percentage),
        legend=layout.legend)
    _validate_chart_path(path)
    _prepare_report_path(path)
    write_svg_line_chart(path, lines, options)
    return nothing
end

function _normalize_values(values::AbstractVector{Float64})::Vector{Float64}
    isempty(values) && throw(ArgumentError("Normalization requires at least one observation."))
    isfinite(first(values)) && first(values) > 0.0 ||
        throw(ArgumentError("Normalization requires a positive finite first observation."))
    return values ./ first(values)
end

"""
    write_performance_charts(paths, timestamps, equity, benchmark, drawdowns, y_axis_scale)

Write the equity and normalized-performance charts with strategy drawdown on a right axis that
spans -100% to 0%. `benchmark` is `nothing` or a `(label, levels)` pair; levels are positive and
drawdowns are fractions in `[-1, 0]`. An existing separate `drawdown.svg` is removed.
"""
function write_performance_charts(paths::StandardReportOutputPaths, timestamps::AbstractVector{DateTime},
    equity::AbstractVector{Float64}, benchmark, drawdowns::AbstractVector{Float64}, y_axis_scale::Symbol)::Nothing
    y_axis_scale in CHART_Y_SCALES ||
        throw(ArgumentError("Chart y-axis scale must be :linear or :logarithmic; received $(repr(y_axis_scale))."))
    for (label, values) in Iterators.flatten(((("strategy", equity),), isnothing(benchmark) ? () : (benchmark,)))
        length(values) == length(timestamps) && all(value -> isfinite(value) && value > 0.0, values) ||
            throw(ArgumentError("Performance series '$(label)' requires one positive finite level per timestamp."))
    end
    layout = ChartLayout(STANDARD_CHART_LAYOUT.size, STANDARD_CHART_LAYOUT.legend, false, collect(Float64, drawdowns))
    _write_chart(paths.equity_chart, "Strategy equity and drawdown", _performance_y_axis_label("base currency", y_axis_scale),
        timestamps, [("strategy", equity, CHART_PRIMARY)], y_axis_scale, layout)
    normalized = Any[("strategy", _normalize_values(equity), CHART_PRIMARY)]
    isnothing(benchmark) || push!(normalized, (benchmark[1], _normalize_values(benchmark[2]), CHART_SECONDARY))
    _write_chart(paths.normalized_chart, "Normalized performance and strategy drawdown",
        _performance_y_axis_label("normalized level", y_axis_scale), timestamps, normalized, y_axis_scale, layout)
    rm(joinpath(dirname(paths.equity_chart), "drawdown.svg"); force=true)
    return nothing
end

"""
    write_with_markdown_appendix(report, appendix) -> StandardReportOutputPaths

Write the Markdown report with a caller-rendered appendix, the observation and trade Parquet
exports, and the equity, normalized, exposure, and turnover charts.
"""
function write_with_markdown_appendix(report::StandardBacktestReport, appendix::AbstractString)::StandardReportOutputPaths
    mkpath(dirname(report.paths.report))
    write(report.paths.report, render_markdown(report) * appendix)
    observations = report.observations
    timestamps = [observation.timestamp for observation in observations]
    equity = [observation.equity for observation in observations]
    benchmark = isnothing(first(observations).benchmark_equity) ? nothing :
        [something(observation.benchmark_equity) for observation in observations]
    benchmark_drawdowns = isnothing(benchmark) ? nothing : _drawdown_fractions(something(benchmark))
    _write_parquet(report.paths.observations, (
        timestamp=timestamps,
        strategy_return_pct=vcat(0.0, [period.strategy_return * 100.0 for period in report.period_returns]),
        strategy_equity=equity,
        strategy_normalized=equity ./ first(equity),
        strategy_drawdown_pct=report.drawdowns .* 100.0,
        benchmark_return_pct=isnothing(benchmark) ? fill(missing, length(timestamps)) :
            vcat(0.0, [something(period.benchmark_return) * 100.0 for period in report.period_returns]),
        benchmark_equity=isnothing(benchmark) ? fill(missing, length(timestamps)) : something(benchmark),
        benchmark_normalized=isnothing(benchmark) ? fill(missing, length(timestamps)) : something(benchmark) ./ first(something(benchmark)),
        benchmark_drawdown_pct=isnothing(benchmark) ? fill(missing, length(timestamps)) : something(benchmark_drawdowns) .* 100.0,
        gross_exposure=[observation.gross_exposure for observation in observations],
        net_exposure=[observation.net_exposure for observation in observations],
        cash_weight=[observation.cash_weight for observation in observations],
        round_trip_turnover=report.turnover,
    ))
    _write_parquet(report.paths.trades, (
        trade_id=UInt64[trade.tid for trade in report.trades],
        timestamp=DateTime[trade.date for trade in report.trades],
        symbol=String[String(trade.order.inst.spec.symbol) for trade in report.trades],
        fill_price=Float64[trade.fill_price for trade in report.trades],
        fill_quantity=Float64[trade.fill_qty for trade in report.trades],
        notional_base=Float64[trade.notional_base for trade in report.trades],
        commission_settlement=Float64[trade.commission_settle for trade in report.trades],
        realized_quantity=Float64[trade.realized_qty for trade in report.trades],
    ))
    write_performance_charts(report.paths, timestamps, equity,
        isnothing(benchmark) ? nothing : (report.spec.benchmark_label, something(benchmark)), report.drawdowns,
        report.spec.performance_y_axis_scale)
    _write_chart(report.paths.exposure_chart, "Exposure", "equity fraction", timestamps,
        [("gross", [o.gross_exposure for o in observations], CHART_PRIMARY),
            ("net", [o.net_exposure for o in observations], CHART_SECONDARY),
            ("cash", [o.cash_weight for o in observations], CHART_CASH)], :linear, COMPACT_CHART_LAYOUT)
    _write_chart(report.paths.turnover_chart, "Round-trip turnover", "equity fraction", timestamps,
        [("turnover", report.turnover, CHART_PRIMARY)], :linear, COMPACT_CHART_LAYOUT_WITHOUT_LEGEND)
    return report.paths
end

Base.write(report::StandardBacktestReport) = write_with_markdown_appendix(report, "")

# Causal benchmark

"""
A buy-and-hold benchmark compounded from causal prices: the first price sets its base, an exact
repeat is ignored, and a conflicting or regressing price fails.
"""
mutable struct CausalBuyAndHoldBenchmark
    label::String
    equity::Float64
    latest::Union{Nothing,Tuple{DateTime,Float64}}

    function CausalBuyAndHoldBenchmark(label::AbstractString, initial_equity::Real)
        !isempty(label) && strip(label) == label ||
            throw(ArgumentError("Buy-and-hold benchmark label must be nonempty without surrounding whitespace."))
        isfinite(initial_equity) && initial_equity > 0 ||
            throw(ArgumentError("$(label) benchmark initial equity must be positive and finite, received $(initial_equity)."))
        return new(String(label), Float64(initial_equity), nothing)
    end
end

"""Apply a causal price observation and return the benchmark equity."""
function observe!(benchmark::CausalBuyAndHoldBenchmark, observed_at::DateTime, price::Real)::Float64
    isfinite(price) && price > 0 ||
        throw(ArgumentError("$(benchmark.label) benchmark price must be positive and finite, received $(price)."))
    if !isnothing(benchmark.latest)
        previous_at, previous_price = something(benchmark.latest)
        observed_at < previous_at &&
            throw(ArgumentError("$(benchmark.label) benchmark observation at $(observed_at) precedes $(previous_at)."))
        if observed_at == previous_at
            Float64(price) === previous_price && return benchmark.equity
            throw(ArgumentError("$(benchmark.label) benchmark observation at $(observed_at) conflicts with $(previous_price)."))
        end
        benchmark.equity *= price / previous_price
        isfinite(benchmark.equity) && benchmark.equity > 0 ||
            throw(ArgumentError("$(benchmark.label) benchmark produced invalid equity $(benchmark.equity)."))
    end
    benchmark.latest = (observed_at, Float64(price))
    return benchmark.equity
end

"""The benchmark equity carried forward to `timestamp` without a new price."""
function carry(benchmark::CausalBuyAndHoldBenchmark, timestamp::DateTime)::Float64
    isnothing(benchmark.latest) &&
        throw(ArgumentError("$(benchmark.label) benchmark cannot carry at $(timestamp) before its first observation."))
    observed_at = first(something(benchmark.latest))
    timestamp < observed_at &&
        throw(ArgumentError("$(benchmark.label) benchmark cannot carry backward from $(observed_at) to $(timestamp)."))
    return benchmark.equity
end

# Diagnostics

"""A named series of finite values; the name becomes its Parquet column and chart label."""
struct DiagnosticSeries
    name::String
    values::Vector{Float64}

    function DiagnosticSeries(name::AbstractString, values::AbstractVector{<:Real})
        !isempty(name) && strip(name) == name && name != "timestamp" ||
            throw(ArgumentError("Diagnostic series name must be nonempty, non-reserved, and have no surrounding whitespace."))
        index = findfirst(value -> !isfinite(value), values)
        isnothing(index) ||
            throw(ArgumentError("Diagnostic series '$(name)' contains non-finite value $(values[index]) at index $(index)."))
        return new(String(name), collect(Float64, values))
    end
end

function _validate_diagnostic_table(timestamps::AbstractVector{DateTime}, series::AbstractVector{DiagnosticSeries})
    all(index -> timestamps[index - 1] < timestamps[index], 2:length(timestamps)) ||
        throw(ArgumentError("Diagnostic timestamps must strictly increase."))
    isempty(series) && throw(ArgumentError("Diagnostic table requires at least one series."))
    names = Set{String}()
    for item in series
        item.name in names && throw(ArgumentError("Duplicate diagnostic series '$(item.name)'."))
        push!(names, item.name)
        length(item.values) == length(timestamps) || throw(ArgumentError(
            "Diagnostic series '$(item.name)' has $(length(item.values)) values for $(length(timestamps)) timestamps.",
        ))
    end
    return nothing
end

"""Write timestamped diagnostic series as one Parquet table."""
function write_diagnostic_parquet(path::AbstractString, timestamps::AbstractVector{DateTime},
    series::AbstractVector{DiagnosticSeries})::Nothing
    _validate_diagnostic_table(timestamps, series)
    _write_parquet(path, (; :timestamp => collect(timestamps), (Symbol(item.name) => item.values for item in series)...))
    return nothing
end

"""Write timestamped diagnostic columns of any Parquet type, given as a named tuple of equal-length vectors."""
function write_typed_diagnostic_parquet(path::AbstractString, timestamps::AbstractVector{DateTime}, columns::NamedTuple)::Nothing
    all(index -> timestamps[index - 1] < timestamps[index], 2:length(timestamps)) ||
        throw(ArgumentError("Diagnostic timestamps must strictly increase."))
    haskey(columns, :timestamp) && throw(ArgumentError("Diagnostic column name 'timestamp' is reserved."))
    all(column -> length(column) == length(timestamps), values(columns)) ||
        throw(ArgumentError("Diagnostic columns must align with timestamps."))
    _write_parquet(path, merge((; timestamp=collect(timestamps)), columns))
    return nothing
end

"""Timestamp-aligned diagnostics of one to four unique series, rendered in the standard artifact style."""
struct DiagnosticTimeSeries
    timestamps::Vector{DateTime}
    series::Vector{DiagnosticSeries}

    function DiagnosticTimeSeries(timestamps::AbstractVector{DateTime}, series::AbstractVector{DiagnosticSeries})
        _validate_diagnostic_table(timestamps, series)
        length(series) <= 4 || throw(ArgumentError("Diagnostic time series requires between one and four series."))
        return new(collect(timestamps), collect(series))
    end
end

"""Write the diagnostic table as Parquet and its compact SVG chart."""
function Base.write(diagnostics::DiagnosticTimeSeries, parquet_path::AbstractString, chart_path::AbstractString,
    title::AbstractString, y_label::AbstractString)::Nothing
    _prepare_report_path(parquet_path)
    _prepare_report_path(chart_path)
    _validate_chart_path(chart_path)
    !isempty(title) && !isempty(y_label) ||
        throw(ArgumentError("Diagnostic chart title and y-axis label must be nonempty."))
    write_diagnostic_parquet(parquet_path, diagnostics.timestamps, diagnostics.series)
    colors = (CHART_PRIMARY, CHART_SECONDARY, CHART_CASH, CHART_NEGATIVE)
    _write_chart(chart_path, title, y_label, diagnostics.timestamps,
        [(item.name, item.values, color) for (item, color) in zip(diagnostics.series, colors)], :linear, COMPACT_CHART_LAYOUT)
    return nothing
end

"""
    write_normalized_performance_comparison(chart_path, parquet_path, timestamps, series, title)

Write normalized positive paths as a logarithmic comparison chart and a long Parquet table of each
path's period return, level, and drawdown. Input order is kept and the final path, typically a
portfolio appended after its components, is emphasized.
"""
write_normalized_performance_comparison(chart_path::AbstractString, parquet_path::AbstractString,
    timestamps::AbstractVector{DateTime}, series::AbstractVector{DiagnosticSeries}, title::AbstractString) =
    write_normalized_performance_comparison_with_y_axis_scale(chart_path, parquet_path, timestamps, series, title, :logarithmic)

"""Write a normalized performance comparison with an explicit `:linear` or `:logarithmic` chart scale."""
function write_normalized_performance_comparison_with_y_axis_scale(chart_path::AbstractString, parquet_path::AbstractString,
    timestamps::AbstractVector{DateTime}, series::AbstractVector{DiagnosticSeries}, title::AbstractString,
    y_axis_scale::Symbol)::Nothing
    _validate_diagnostic_table(timestamps, series)
    length(timestamps) >= 2 || throw(ArgumentError("Performance comparison requires at least two timestamps."))
    !isempty(title) && strip(title) == title ||
        throw(ArgumentError("Performance comparison title must be nonempty without surrounding whitespace."))
    y_axis_scale in CHART_Y_SCALES ||
        throw(ArgumentError("Chart y-axis scale must be :linear or :logarithmic; received $(repr(y_axis_scale))."))
    _prepare_report_path(chart_path)
    _prepare_report_path(parquet_path)
    _validate_chart_path(chart_path)
    normalized = map(series) do item
        first(item.values) > 0.0 && all(>(0.0), item.values) ||
            throw(ArgumentError("Performance path '$(item.name)' requires positive values."))
        item.values ./ first(item.values)
    end
    columns = (timestamp=DateTime[], strategy_id=String[], strategy_return_pct=Float64[], strategy_equity=Float64[],
        strategy_normalized=Float64[], strategy_drawdown_pct=Float64[])
    peaks = ones(length(series))
    for (row, timestamp) in enumerate(timestamps), (index, item) in enumerate(series)
        value = normalized[index][row]
        peaks[index] = max(peaks[index], value)
        push!(columns.timestamp, timestamp)
        push!(columns.strategy_id, item.name)
        push!(columns.strategy_return_pct, row == 1 ? 0.0 : (value / normalized[index][row - 1] - 1.0) * 100.0)
        push!(columns.strategy_equity, value)
        push!(columns.strategy_normalized, value)
        push!(columns.strategy_drawdown_pct, (value / peaks[index] - 1.0) * 100.0)
    end
    _write_parquet(parquet_path, columns)
    chart_series = [(item.name, normalized[index],
        index == length(series) ? CHART_PRIMARY : SERIES_PALETTE[2 + mod(index - 1, length(SERIES_PALETTE) - 1)])
                    for (index, item) in enumerate(series)]
    _write_chart(chart_path, title, _performance_y_axis_label("normalized level", y_axis_scale), timestamps, chart_series,
        y_axis_scale, ChartLayout(STANDARD_CHART_LAYOUT.size, 3, true, nothing))
    return nothing
end

end # module Artifacts
