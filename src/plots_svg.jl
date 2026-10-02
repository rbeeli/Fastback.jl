# Built-in SVG backend of the plotting interface, rendered by `Fastback.Charts`.
#
# Every SVG method accepts the shared keywords `title`, `width`, `height`, `legend::Bool`, and
# `ylims`; collector plots also accept `xaxis_mode` (`:date` or `:index`). Plots without finite
# samples throw an `ArgumentError`.
using Dates
using .Charts: AxisOptions, ChartOptions, LineSeries, ScatterSeries, StackedBarSeries,
    render_svg_line_chart, render_svg_scatter_chart, render_svg_stacked_bar_chart

function _svg_options(
    title
    ;
    width::Integer=1_600,
    height::Integer=900,
    legend::Bool=false,
    ylims=nothing,
    y_label=nothing,
    y_format::Symbol=:number,
    y_tick_count::Integer=6,
    right_y_axis=nothing,
)
    limits = ylims === nothing ? nothing : (Float64(ylims[1]), Float64(ylims[2]))
    ChartOptions(; width=Int(width), height=Int(height), title=String(title),
        left_y_axis=AxisOptions(; limits, label=y_label === nothing ? nothing : String(y_label),
            format=y_format, tick_count=Int(y_tick_count)),
        right_y_axis, legend=legend ? 6 : nothing)
end

function _svg_x(pv, xaxis_mode::Symbol)
    xaxis_mode in (:date, :index) || throw(ArgumentError("xaxis_mode must be :date or :index."))
    xaxis_mode === :date ? dates(pv) : collect(1:length(values(pv)))
end

_svg_write(io::IO, svg::String) = (print(io, svg); io)

function _svg_collector_line!(io, pv, title, label, color; xaxis_mode=:date, kwargs...)
    series = [LineSeries(label, _svg_x(pv, xaxis_mode), values(pv); color)]
    _svg_write(io, render_svg_line_chart(series, _svg_options(title; kwargs...)))
end

function plot_balance!(
    backend::SVGBackend,
    io::IO,
    pv::PeriodicValues
    ;
    title="Balance",
    label="Cash balance",
    color=_PLOT_COLORS.balance,
    kwargs...,
)
    _svg_collector_line!(io, pv, title, label, color; kwargs...)
end

function plot_equity!(
    backend::SVGBackend,
    io::IO,
    pv::PeriodicValues
    ;
    title="Equity",
    label="Equity",
    color=_PLOT_COLORS.equity,
    kwargs...,
)
    _svg_collector_line!(io, pv, title, label, color; kwargs...)
end

function plot_open_orders_count!(
    backend::SVGBackend,
    io::IO,
    pv::PeriodicValues
    ;
    title="Open orders count",
    label="Open orders count",
    color=_PLOT_COLORS.open_orders,
    ylims=nothing,
    kwargs...,
)
    bounds, ticks = _plot_count_axis(values(pv); ylims)
    _svg_collector_line!(io, pv, title, label, color; ylims=bounds, y_tick_count=max(2, length(ticks)), kwargs...)
end

function plot_drawdown!(
    backend::SVGBackend,
    io::IO,
    pv::DrawdownValues
    ;
    title="Equity drawdowns",
    ylims=pv.mode == DrawdownMode.Percentage ? (-1.0, 0.0) : nothing,
    kwargs...,
)
    format = pv.mode == DrawdownMode.Percentage ? :percentage : :number
    _svg_collector_line!(io, pv, title, "Drawdown", _PLOT_COLORS.drawdown; ylims, y_format=format, kwargs...)
end

function plot_equity_drawdown!(
    backend::SVGBackend,
    io::IO,
    equity::PeriodicValues,
    dd::DrawdownValues
    ;
    title="Equity & drawdown",
    xaxis_mode=:date,
    show_max_dd::Bool=true,
    kwargs...,
)
    x = _svg_x(equity, xaxis_mode)
    equity_values = values(equity)
    series = [LineSeries("Equity", x, equity_values; color=_PLOT_COLORS.equity),
        LineSeries("Drawdown", _svg_x(dd, xaxis_mode), values(dd); axis=:right, color=_PLOT_COLORS.drawdown)]

    if show_max_dd
        peak, trough, _ = _plot_max_drawdown_indices(equity_values, dd.mode)

        if peak != 0
            # Only the peak and trough are finite, so the series renders as two markers.
            markers = fill(NaN, length(equity_values))
            markers[[peak, trough]] = equity_values[[peak, trough]]
            push!(series, LineSeries("Max drawdown", x, markers; color=_PLOT_COLORS.drawdown))
        end
    end

    pct = dd.mode == DrawdownMode.Percentage
    right_axis = AxisOptions(; label="Drawdown", format=pct ? :percentage : :number,
        limits=pct ? (-1.0, 0.0) : nothing)
    options = _svg_options(title; y_label="Equity", right_y_axis=right_axis, kwargs...)
    _svg_write(io, render_svg_line_chart(series, options))
end

function plot_exposure!(
    backend::SVGBackend,
    io::IO
    ;
    gross=nothing,
    net=nothing,
    long=nothing,
    short=nothing,
    title="Exposure",
    legend::Bool=true,
    xaxis_mode=:date,
    kwargs...,
)
    series = [LineSeries(label, _svg_x(pv, xaxis_mode), values(pv); color) for (pv, label, color) in
        ((gross, "Gross", _PLOT_COLORS.exposure_gross), (net, "Net", _PLOT_COLORS.exposure_net),
        (long, "Long", _PLOT_COLORS.exposure_long), (short, "Short", _PLOT_COLORS.exposure_short)) if pv !== nothing]
    _svg_write(io, render_svg_line_chart(series, _svg_options(title; legend, kwargs...)))
end

# Each bar spans from its date to the next; the last spans the preceding interval, or one
# second (one day for `Date`) when there is a single date.
function _svg_bar_boundaries(dts::AbstractVector{<:Dates.AbstractTime})
    isempty(dts) && throw(ArgumentError("Portfolio weights require at least one date."))
    width = length(dts) >= 2 ? dts[end] - dts[end - 1] : (eltype(dts) <: Date ? Day(1) : Second(1))
    vcat(collect(dts), dts[end] + width)
end

function plot_portfolio_weights_over_time!(
    backend::SVGBackend,
    io::IO,
    dts::AbstractVector{<:Dates.AbstractTime},
    weights::AbstractMatrix{<:Real},
    symbols::AbstractVector
    ;
    title="Portfolio weights over time",
    legend::Bool=true,
    kwargs...,
)
    size(weights) == (length(dts), length(symbols)) ||
        throw(ArgumentError("Weights must have one row per date and one column per symbol."))
    series = [StackedBarSeries(string(symbol), weights[:, j]) for (j, symbol) in enumerate(symbols)]
    options = _svg_options(title; legend, y_format=:percentage, kwargs...)
    _svg_write(io, render_svg_stacked_bar_chart(_svg_bar_boundaries(dts), series, options))
end

function plot_portfolio_weights_over_time!(
    backend::SVGBackend,
    io::IO,
    pv::PortfolioWeightsValues
    ;
    kwargs...,
)
    weights = Matrix{Float64}(undef, length(dates(pv)), length(pv.symbols))

    for j in eachindex(pv.symbols)
        length(pv.weights[j]) == size(weights, 1) || throw(ArgumentError("Weight series length must match dates."))
        weights[:, j] = pv.weights[j]
    end

    plot_portfolio_weights_over_time!(backend, io, dates(pv), weights, pv.symbols; kwargs...)
end

function plot_cashflows!(
    backend::SVGBackend,
    io::IO,
    acc::Account
    ;
    title="Cashflows",
    legend::Bool=true,
    kwargs...,
)
    isempty(acc.cashflows) && throw(ArgumentError("Account has no cashflows to plot."))
    # One marker series per kind, in recorded native amounts, matching the Plots backend.
    series = map(sort!(unique(cf.kind for cf in acc.cashflows); by=Int)) do kind
        cfs = filter(cf -> cf.kind == kind, acc.cashflows)
        ScatterSeries(string(kind), [cf.dt for cf in cfs], [cf.amount for cf in cfs])
    end
    _svg_write(io, render_svg_scatter_chart(series, _svg_options(title; legend, kwargs...)))
end

function _svg_returns!(
    io,
    trades,
    groupby
    ;
    return_basis=:gross,
    xaxis_mode=:date,
    title="Realized cumulative returns",
    legend::Bool=true,
    kwargs...,
)
    return_basis in (:gross, :net) || throw(ArgumentError("return_basis must be :gross or :net."))
    xaxis_mode in (:date, :index) || throw(ArgumentError("xaxis_mode must be :date or :index."))
    ret = return_basis === :gross ? realized_return_gross : realized_return_net
    groups = Dict{Int,Vector{eltype(trades)}}()

    for t in trades
        is_realizing(t) || continue
        push!(get!(groups, groupby(t.date), eltype(trades)[]), t)
    end

    series = LineSeries[]

    for key in sort!(collect(keys(groups)))
        group = sort!(groups[key]; by=t -> t.date)
        dts = typeof(first(group).date)[]
        nums, dens = Float64[], Float64[]

        for t in group
            r, w = ret(t), realized_notional_quote(t)
            isnan(r) && continue
            isfinite(w) && w > 0 || continue

            if isempty(dts) || dts[end] != t.date
                push!(dts, t.date); push!(nums, 0.0); push!(dens, 0.0)
            end

            nums[end] += r * w
            dens[end] += w
        end

        isempty(dts) && continue
        ys = cumprod(1 .+ nums ./ dens) .- 1
        label = groupby === Dates.hour ? "$(key):00" : Dates.dayname(key)
        push!(series, LineSeries(label, xaxis_mode === :date ? dts : collect(eachindex(ys)), ys))
    end

    isempty(series) && throw(ArgumentError("No realized trades with finite returns to plot."))
    _svg_write(io, render_svg_line_chart(series, _svg_options(title; legend, y_format=:percentage, kwargs...)))
end

function plot_realized_cum_returns_by_hour!(
    backend::SVGBackend,
    io::IO,
    trades::AbstractVector{<:Trade}
    ;
    kwargs...,
)
    _svg_returns!(io, trades, Dates.hour; kwargs...)
end

function plot_realized_cum_returns_by_weekday!(
    backend::SVGBackend,
    io::IO,
    trades::AbstractVector{<:Trade}
    ;
    kwargs...,
)
    _svg_returns!(io, trades, Dates.dayofweek; kwargs...)
end

function _render_svg(
    render!::Function,
    backend::SVGBackend,
    args...
    ;
    output_format::Symbol=svg_output_format(),
    kwargs...,
)
    _validate_svg_output_format(output_format)
    svg = sprint(io -> render!(backend, io, args...; kwargs...))
    output_format === :html ? Base.HTML(svg) : svg
end

for name in (:plot_balance, :plot_equity, :plot_open_orders_count, :plot_drawdown, :plot_equity_drawdown,
    :plot_exposure, :plot_portfolio_weights_over_time, :plot_cashflows, :plot_realized_cum_returns_by_hour,
    :plot_realized_cum_returns_by_weekday)
    @eval $name(backend::SVGBackend, args...; kwargs...) = _render_svg($(Symbol(name, :!)), backend, args...; kwargs...)
end
