module FastbackPlotsExt

using Fastback
using Dates
using Printf
using Plots
using Query

const _HAS_STATSPLOTS = Ref(false)
const _THEME_KW = (titlelocation=:left, titlefontsize=10, widen=false, fg_legend=:false)
const _COLOR_BALANCE = "#0088DD"
const _COLOR_EQUITY = "#BBBB00"
const _COLOR_OPEN_ORDERS = "#00B8D9"
const _COLOR_DRAWDOWN = "#BB0000"
const _FILL_DRAWDOWN = "#BB000033"
const _COLOR_EXPOSURE_GROSS = "#444444"
const _COLOR_EXPOSURE_NET = "#0066BB"
const _COLOR_EXPOSURE_LONG = "#22AA66"
const _COLOR_EXPOSURE_SHORT = "#CC4444"

@inline function _ensure_statsplots()
    if _HAS_STATSPLOTS[]
        return
    end
    try
        @eval import StatsPlots
        _HAS_STATSPLOTS[] = true
        return
    catch err
        err_msg = sprint(showerror, err)
        throw(ArgumentError("StatsPlots is required for violin plots. Install it with `import Pkg; Pkg.add(\"StatsPlots\")`. Import error: $(err_msg)"))
    end
end

@inline function _merge_kwargs(defaults::NamedTuple, kwargs)
    merge(defaults, (; kwargs...))
end
@inline function _with_theme(f::Function)
    Plots.with(; _THEME_KW...) do
        f()
    end
end

@inline function _empty_plot(title_text; kwargs...)
    _with_theme() do
        plot_kwargs = _merge_kwargs((; title=title_text), kwargs)
        Plots.plot(; plot_kwargs...)
    end
end

@inline function _balance_kwargs()
    (;
        label="Cash balance",
        linecolor=_COLOR_BALANCE,
        linetype=:steppost,
        yformatter=y -> @sprintf("%.0f", y),
        w=1,
    )
end

@inline function _equity_kwargs()
    (;
        label="Equity",
        linecolor=_COLOR_EQUITY,
        linetype=:steppost,
        yformatter=y -> @sprintf("%.0f", y),
        w=1,
    )
end

@inline function _open_orders_count_kwargs(vals)
    max_open = maximum(vals)
    max_tick = max(0, floor(Int, max_open))
    y_ticks = 0:max_tick
    y_ticks_str = map(x -> @sprintf("%.0f", x), y_ticks)
    base = (;
        label="# open orders",
        linecolor=_COLOR_OPEN_ORDERS,
        linetype=:steppost,
        yticks=(y_ticks, y_ticks_str),
        legend=false,
    )
    base, max_open
end

@inline function _drawdown_kwargs(pv::DrawdownValues)
    (;
        label="Drawdown",
        fill=(0, _FILL_DRAWDOWN),
        linecolor=_COLOR_DRAWDOWN,
        linetype=:steppost,
        yformatter=(pv.mode == DrawdownMode.Percentage ? (y -> @sprintf("%.1f%%", 100y)) : (y -> @sprintf("%.0f", y))),
        w=1,
        legend=false,
    )
end

@inline function _exposure_kwargs(label::AbstractString, color)
    (;
        label=label,
        linecolor=color,
        linetype=:steppost,
        yformatter=y -> @sprintf("%.0f", y),
        w=1,
    )
end

@inline function _has_values(pv)
    pv !== nothing && !isempty(values(pv))
end

@inline function _plot_exposure_series!(
    plt,
    pv,
    label::AbstractString,
    color;
    kwargs...
)
    _has_values(pv) || return plt
    plot_kwargs = _merge_kwargs(_exposure_kwargs(label, color), kwargs)
    Plots.plot!(plt, dates(pv), values(pv); plot_kwargs...)
    plt
end

@inline function _drawdown_axis_label(pv::DrawdownValues)
    pv.mode == DrawdownMode.Percentage ? "Drawdown [%]" : "Drawdown"
end

@inline function _max_drawdown_indices(vals::AbstractVector{<:Real})
    n = length(vals)
    n == 0 && return 0, 0, 0.0
    max_val = Float64(vals[1])
    max_idx = 1
    peak_idx = 1
    trough_idx = 1
    max_dd = 0.0
    for i in 2:n
        v = Float64(vals[i])
        if v > max_val
            max_val = v
            max_idx = i
        end
        dd = v - max_val
        if dd < max_dd
            max_dd = dd
            peak_idx = max_idx
            trough_idx = i
        end
    end
    peak_idx, trough_idx, max_dd
end

@inline function _drawdown_value(peak_val::Real, trough_val::Real, mode::DrawdownMode.T)
    dd = Float64(trough_val - peak_val)
    if mode == DrawdownMode.Percentage
        return peak_val == 0 ? 0.0 : dd / peak_val
    end
    dd
end

function _add_max_drawdown_markers!(
    plt,
    dts::AbstractVector{<:Dates.AbstractTime},
    vals::AbstractVector{<:Real},
    mode::DrawdownMode.T;
    drawdown_axis::Bool=true,
    drawdown_plot=nothing,
)
    peak_idx, trough_idx, max_dd = _max_drawdown_indices(vals)
    max_dd < 0 || return plt
    peak_dt, trough_dt = dts[peak_idx], dts[trough_idx]
    peak_val, trough_val = vals[peak_idx], vals[trough_idx]
    _with_theme() do
        Plots.scatter!(plt, [peak_dt], [peak_val];
            marker=:utriangle,
            markersize=4,
            color=_COLOR_DRAWDOWN,
            label=false)
        Plots.scatter!(plt, [trough_dt], [trough_val];
            marker=:dtriangle,
            markersize=4,
            color=_COLOR_DRAWDOWN,
            label=false)
        if drawdown_axis
            dd_val = _drawdown_value(peak_val, trough_val, mode)
            target = isnothing(drawdown_plot) ? plt : drawdown_plot
            Plots.scatter!(target, [trough_dt], [dd_val];
                marker=:circle,
                markersize=4,
                color=_COLOR_DRAWDOWN,
                label="Max drawdown")
        end
    end
    plt
end

struct PlotEvent{TTime<:Dates.AbstractTime}
    open_dt::TTime
    last_dt::TTime
    ret::Float64
end

@inline PlotEvent(open_dt::TTime, last_dt::TTime, ret::Real) where {TTime<:Dates.AbstractTime} =
    PlotEvent{TTime}(open_dt, last_dt, Float64(ret))

@inline PlotEvent(t::Trade{T}) where {T<:Dates.AbstractTime} =
    PlotEvent{T}(t.date, t.date, realized_return(t))

"""
Render a title-only plot panel.
"""
function Fastback.plot_title(title_text; kwargs...)
    plot_kwargs = _merge_kwargs((;
            marker=0,
            markeralpha=0,
            annotations=(1.5, 1.5, title_text),
            foreground_color_subplot=:white,
            axis=false,
            grid=false,
            leg=false,
        ), kwargs)
    _with_theme() do
        Plots.scatter(1:2; plot_kwargs...)
    end
end

"""
Plot cash balance over time from `PeriodicValues`.
"""
function Fastback.plot_balance(pv::PeriodicValues; kwargs...)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No balance data"; kwargs...)
    plt = Plots.plot()
    Fastback.plot_balance!(plt, pv; title="Balance", legend=false, kwargs...)
    Plots.ylims!(plt, (0, maximum(vals)))
    plt
end

"""
Add cash balance series to an existing plot.
"""
function Fastback.plot_balance!(plt, pv::PeriodicValues; kwargs...)
    dts, vals = dates(pv), values(pv)
    isempty(vals) && return plt
    plot_kwargs = _merge_kwargs(_balance_kwargs(), kwargs)
    _with_theme() do
        Plots.plot!(plt, dts, vals; plot_kwargs...)
    end
    plt
end

"""
Plot equity over time from `PeriodicValues`.
"""
function Fastback.plot_equity(pv::PeriodicValues; kwargs...)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No equity data"; kwargs...)
    plt = Plots.plot()
    Fastback.plot_equity!(plt, pv; title="Equity", legend=false, kwargs...)
    plt
end

"""
Add equity series to an existing plot.
"""
function Fastback.plot_equity!(plt, pv::PeriodicValues; kwargs...)
    dts, vals = dates(pv), values(pv)
    isempty(vals) && return plt
    plot_kwargs = _merge_kwargs(_equity_kwargs(), kwargs)
    _with_theme() do
        Plots.plot!(plt, dts, vals; plot_kwargs...)
    end
    plt
end

"""
Plot equity by sequence index (no datetime axis).
"""
function Fastback.plot_equity_seq(pv::PeriodicValues; kwargs...)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No equity data"; kwargs...)
    x = collect(1:length(vals))
    plot_kwargs = _merge_kwargs((;
            title="Equity",
            linecolor=_COLOR_EQUITY,
            linetype=:steppost,
            yformatter=y -> @sprintf("%.0f", y),
            w=1,
            legend=false,
        ), kwargs)
    _with_theme() do
        Plots.plot(x, vals; plot_kwargs...)
    end
end

"""
Plot open orders over time from `PeriodicValues`.
"""
function Fastback.plot_open_orders_count(pv::PeriodicValues; kwargs...)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No open orders data"; kwargs...)
    plt = Plots.plot()
    Fastback.plot_open_orders_count!(plt, pv; title="# open orders", legend=false, kwargs...)
    plt
end

"""
Add open orders series to an existing plot.
"""
function Fastback.plot_open_orders_count!(plt, pv::PeriodicValues; kwargs...)
    dts, vals = dates(pv), values(pv)
    isempty(vals) && return plt
    plot_kwargs, max_open = _open_orders_count_kwargs(vals)
    plot_kwargs = _merge_kwargs(plot_kwargs, kwargs)
    _with_theme() do
        Plots.plot!(plt, dts, vals; plot_kwargs...)
        Plots.ylims!(plt, (0, max(0, max_open)))
    end
    plt
end

"""
Plot open orders by sequence index (no datetime axis).
"""
function Fastback.plot_open_orders_count_seq(pv::PeriodicValues; kwargs...)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No open orders data"; kwargs...)
    x = collect(1:length(vals))
    max_open = maximum(vals)
    max_tick = max(0, floor(Int, max_open))
    y_ticks = 0:max_tick
    y_ticks_str = map(x -> @sprintf("%.0f", x), y_ticks)

    plot_kwargs = _merge_kwargs((;
            title="# open orders",
            linecolor=_COLOR_OPEN_ORDERS,
            linetype=:steppost,
            yticks=(y_ticks, y_ticks_str),
            legend=false,
        ), kwargs)
    _with_theme() do
        plt = Plots.plot(x, vals; plot_kwargs...)
        Plots.ylims!(plt, (0, max(0, max_open)))
        plt
    end
end

"""
Plot drawdown series from `DrawdownValues`.
"""
function Fastback.plot_drawdown(pv::DrawdownValues; kwargs...)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No drawdown data"; kwargs...)
    title = (pv.mode == DrawdownMode.Percentage ? "Equity drawdowns [%]" : "Equity drawdowns")
    plt = Plots.plot()
    Fastback.plot_drawdown!(plt, pv; title=title, legend=false, kwargs...)
    plt
end

"""
Add drawdown series to an existing plot.
"""
function Fastback.plot_drawdown!(plt, pv::DrawdownValues; kwargs...)
    dts, vals = dates(pv), values(pv)
    isempty(vals) && return plt
    plot_kwargs = _merge_kwargs(_drawdown_kwargs(pv), kwargs)
    _with_theme() do
        Plots.plot!(plt, dts, vals; plot_kwargs...)
    end
    plt
end

"""
Plot drawdown by sequence index (no datetime axis).
"""
function Fastback.plot_drawdown_seq(pv::DrawdownValues; kwargs...)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No drawdown data"; kwargs...)
    x = collect(1:length(vals))
    plot_kwargs = _merge_kwargs((;
            title=(pv.mode == DrawdownMode.Percentage ? "Equity drawdowns [%]" : "Equity drawdowns"),
            fill=(0, _FILL_DRAWDOWN),
            linecolor=_COLOR_DRAWDOWN,
            linetype=:steppost,
            yformatter=(pv.mode == DrawdownMode.Percentage ? (y -> @sprintf("%.1f%%", 100y)) : (y -> @sprintf("%.0f", y))),
            w=1,
            legend=false,
        ), kwargs)
    _with_theme() do
        Plots.plot(x, vals; plot_kwargs...)
    end
end

# -----------------------------------------------------------------------------

"""
Plot equity with drawdown overlay and max-drawdown markers.
"""
function Fastback.plot_equity_drawdown(
    equity_pv::PeriodicValues,
    drawdown_pv::DrawdownValues;
    show_max_dd::Bool=true,
    kwargs...
)
    eq_vals = values(equity_pv)
    isempty(eq_vals) && return _empty_plot("No equity data"; kwargs...)
    plt = Plots.plot()
    Fastback.plot_equity_drawdown!(plt, equity_pv, drawdown_pv;
        title="Equity & drawdown",
        legend=:topleft,
        show_max_dd=show_max_dd,
        kwargs...)
    plt
end

"""
Add equity with drawdown overlay and max-drawdown markers to an existing plot.
"""
function Fastback.plot_equity_drawdown!(
    plt,
    equity_pv::PeriodicValues,
    drawdown_pv::DrawdownValues;
    show_max_dd::Bool=true,
    kwargs...
)
    eq_vals = values(equity_pv)
    isempty(eq_vals) && return plt

    Fastback.plot_equity!(plt, equity_pv; kwargs...)

    dd_vals = values(drawdown_pv)
    dd_plot = nothing
    if !isempty(dd_vals)
        legend_val = haskey(kwargs, :legend) ? kwargs[:legend] : :topleft
        dd_kwargs = _merge_kwargs(_drawdown_kwargs(drawdown_pv), (;
            ylabel=_drawdown_axis_label(drawdown_pv),
            legend=legend_val,
        ))
        dd_plot = _with_theme() do
            ax = Plots.twinx(plt)
            Plots.plot!(ax, dates(drawdown_pv), dd_vals; dd_kwargs...)
            ax
        end
    end

    if show_max_dd
        _add_max_drawdown_markers!(
            plt,
            dates(equity_pv),
            eq_vals,
            drawdown_pv.mode;
            drawdown_axis=!isempty(dd_vals),
            drawdown_plot=dd_plot,
        )
    end
    plt
end

# -----------------------------------------------------------------------------

"""
Plot exposure over time (gross, net, long, short).

Pass any combination via keyword arguments: `gross`, `net`, `long`, `short`.
"""
function Fastback.plot_exposure(;
    gross=nothing,
    net=nothing,
    long=nothing,
    short=nothing,
    kwargs...
)
    has_data = _has_values(gross) || _has_values(net) || _has_values(long) || _has_values(short)
    has_data || return _empty_plot("No exposure data"; kwargs...)
    plt = Plots.plot()
    Fastback.plot_exposure!(plt;
        gross=gross,
        net=net,
        long=long,
        short=short,
        title="Exposure",
        legend=:topleft,
        kwargs...)
    plt
end

"""
Add exposure series (gross, net, long, short) to an existing plot.

Pass any combination via keyword arguments: `gross`, `net`, `long`, `short`.
"""
function Fastback.plot_exposure!(
    plt;
    gross=nothing,
    net=nothing,
    long=nothing,
    short=nothing,
    kwargs...
)
    _with_theme() do
        _plot_exposure_series!(plt, gross, "Gross exposure", _COLOR_EXPOSURE_GROSS; kwargs...)
        _plot_exposure_series!(plt, net, "Net exposure", _COLOR_EXPOSURE_NET; kwargs...)
        _plot_exposure_series!(plt, long, "Long exposure", _COLOR_EXPOSURE_LONG; kwargs...)
        _plot_exposure_series!(plt, short, "Short exposure", _COLOR_EXPOSURE_SHORT; kwargs...)
    end
    plt
end

"""
Plot portfolio constituent weights over time as a stacked area chart.

`weights` must be shaped as `(length(dts), length(symbols))`.
"""
function Fastback.plot_portfolio_weights_over_time(
    dts::AbstractVector{<:Dates.AbstractTime},
    weights::AbstractMatrix{<:Real},
    symbols::AbstractVector;
    kwargs...
)
    n_dates = length(dts)
    n_dates == 0 && return _empty_plot("No portfolio weights data"; kwargs...)

    n_weight_rows, n_symbols = size(weights)
    n_weight_rows == n_dates || throw(ArgumentError("`weights` rows ($(n_weight_rows)) must match `dts` length ($(n_dates))."))
    length(symbols) == n_symbols || throw(ArgumentError("`symbols` length ($(length(symbols))) must match `weights` columns ($(n_symbols))."))
    n_symbols == 0 && return _empty_plot("No portfolio constituents"; kwargs...)

    labels = permutedims(string.(symbols))
    weights_matrix = Matrix{Float64}(weights)
    legend_cols = max(1, min(n_symbols, 6))
    plot_kwargs = _merge_kwargs((;
            title="Portfolio weights over time",
            ylabel="Weight",
            yformatter=y -> @sprintf("%.0f%%", 100y),
            label=labels,
            legend=:top,
            legend_column=legend_cols,
            legendfontsize=8,
            foreground_color_legend=nothing,
            background_color_legend=nothing,
            fillalpha=0.85,
            linewidth=0.5,
        ), kwargs)

    _with_theme() do
        Plots.areaplot(dts, weights_matrix; plot_kwargs...)
    end
end

"""
Plot portfolio constituent weights over time from `PortfolioWeightsValues`.
"""
function Fastback.plot_portfolio_weights_over_time(
    pv::PortfolioWeightsValues;
    kwargs...
)
    dts = dates(pv)
    n_dates = length(dts)
    n_dates == 0 && return _empty_plot("No portfolio weights data"; kwargs...)

    symbols = pv.symbols
    n_symbols = length(symbols)
    n_symbols == 0 && return _empty_plot("No portfolio constituents"; kwargs...)

    weights = Matrix{Float64}(undef, n_dates, n_symbols)
    for i in 1:n_symbols
        series = pv.weights[i]
        length(series) == n_dates || throw(ArgumentError("Weight series length ($(length(series))) for symbol $(symbols[i]) must match number of dates ($(n_dates))."))
        @inbounds for j in 1:n_dates
            weights[j, i] = series[j]
        end
    end
    Fastback.plot_portfolio_weights_over_time(dts, weights, symbols; kwargs...)
end

"""
Plot account cashflows by type (one panel per `CashflowKind`).
"""
function Fastback.plot_cashflows(acc::Account{TTime}; kwargs...) where {TTime<:Dates.AbstractTime}
    isempty(acc.cashflows) && return _empty_plot("No cashflow data"; kwargs...)

    cf_by_kind = Dict{CashflowKind.T, Tuple{Vector{TTime}, Vector{Price}}}()
    for cf in acc.cashflows
        dates, amounts = get!(cf_by_kind, cf.kind, (TTime[], Price[]))
        push!(dates, cf.dt)
        push!(amounts, cf.amount)
    end

    kinds = sort!(collect(keys(cf_by_kind)); by=Int)
    plot_kwargs = _merge_kwargs((;
            layout=(length(kinds), 1),
            size=(800, 180 * length(kinds)),
            legend=false,
        ), kwargs)

    _with_theme() do
        p = Plots.plot(; plot_kwargs...)
        for (i, k) in pairs(kinds)
            dates, amounts = cf_by_kind[k]
            Plots.plot!(p[i], dates, amounts;
                seriestype=:sticks,
                marker=:circle,
                markersize=2,
                title=string(k),
                xlabel="Date",
                ylabel=acc.base_currency.symbol,
            )
            Plots.hline!(p[i], [0.0]; color=:black, alpha=0.2)
        end
        p
    end
end

"""
Violin plot of realized returns grouped by day of week (realizing trades only).
"""
function Fastback.plot_violin_realized_returns_by_day(trades::AbstractVector{<:Trade}; kwargs...)
    _ensure_statsplots()
    trades = filter(is_realizing, trades)
    isempty(trades) && return _empty_plot("No realizing trades"; kwargs...)

    groups = trades |>
             @groupby(Dates.dayofweek(_.date)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No realizing trades"; kwargs...)

    y = [map(t -> realized_return(t), group) for (_, group) in groups]
    x_lbls = [Dates.dayname(day) for (day, _) in groups]

    plot_kwargs = _merge_kwargs((;
            xticks=(1:length(y), x_lbls),
            fill="green",
            linewidth=0,
            title="Realized returns by day (trade date)",
            legend=false,
        ), kwargs)
    _with_theme() do
        StatsPlots.violin(y; plot_kwargs...)
    end
end

function Fastback.plot_violin_realized_returns_by_day(events::AbstractVector{<:PlotEvent}; kwargs...)
    _ensure_statsplots()
    isempty(events) && return _empty_plot("No positions"; kwargs...)

    groups = events |>
             @groupby(Dates.dayofweek(_.open_dt)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    y = [map(e -> e.ret, group) for (_, group) in groups]
    x_lbls = [Dates.dayname(day) for (day, _) in groups]

    plot_kwargs = _merge_kwargs((;
            xticks=(1:length(y), x_lbls),
            fill="green",
            linewidth=0,
            title="Realized returns by day (event date)",
            legend=false,
        ), kwargs)
    _with_theme() do
        StatsPlots.violin(y; plot_kwargs...)
    end
end

"""
Violin plot of realized returns grouped by hour (realizing trades only).
"""
function Fastback.plot_violin_realized_returns_by_hour(trades::AbstractVector{<:Trade}; kwargs...)
    _ensure_statsplots()
    trades = filter(is_realizing, trades)
    isempty(trades) && return _empty_plot("No realizing trades"; kwargs...)

    groups = trades |>
             @groupby(Dates.hour(_.date)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No realizing trades"; kwargs...)

    y = [map(t -> realized_return(t), group) for (_, group) in groups]
    x_lbls = [string(hour) for (hour, _) in groups]

    plot_kwargs = _merge_kwargs((;
            xticks=(1:length(y), x_lbls),
            fill="green",
            linewidth=0,
            title="Realized returns by hour (trade time)",
            legend=false,
        ), kwargs)
    _with_theme() do
        StatsPlots.violin(y; plot_kwargs...)
    end
end

function Fastback.plot_violin_realized_returns_by_hour(events::AbstractVector{<:PlotEvent}; kwargs...)
    _ensure_statsplots()
    isempty(events) && return _empty_plot("No positions"; kwargs...)

    groups = events |>
             @groupby(Dates.hour(_.open_dt)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    y = [map(e -> e.ret, group) for (_, group) in groups]
    x_lbls = [string(hour) for (hour, _) in groups]

    plot_kwargs = _merge_kwargs((;
            xticks=(1:length(y), x_lbls),
            fill="green",
            linewidth=0,
            title="Realized returns by hour (event time)",
            legend=false,
        ), kwargs)
    _with_theme() do
        StatsPlots.violin(y; plot_kwargs...)
    end
end

"""
Plot cumulative realized returns grouped by hour (realizing trades only).
"""
function Fastback.plot_realized_cum_returns_by_hour(
    trades::AbstractVector{<:Trade},
    ret_func::Function=t -> realized_return(t);
    kwargs...
)
    trades = filter(is_realizing, trades)
    isempty(trades) && return _empty_plot("No realizing trades"; kwargs...)

    groups = trades |>
             @groupby(Dates.hour(_.date)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No realizing trades"; kwargs...)

    _with_theme() do
        plt = nothing
        for (i, (hour, group)) in enumerate(groups)
            sort!(group, by=t -> t.date)
            dts = map(t -> t.date, group)
            rets = map(ret_func, group)
            cum_rets = cumsum(rets)
            lbl = "$(hour):00+"
            if i == 1
                plot_kwargs = _merge_kwargs((;
                        legend=:topleft,
                        label=lbl,
                        title="Realized returns by hour",
                    ), kwargs)
                plt = Plots.plot(dts, cum_rets; plot_kwargs...)
            else
                series_kwargs = _merge_kwargs((; label=lbl), kwargs)
                Plots.plot!(plt, dts, cum_rets; series_kwargs...)
            end
            if !isempty(dts)
                Plots.annotate!(plt, dts[end], cum_rets[end],
                    Plots.text(lbl, :left, 9))
            end
        end
        plt
    end
end

function Fastback.plot_realized_cum_returns_by_hour(
    events::AbstractVector{<:PlotEvent},
    ret_func::Function=e -> e.ret;
    kwargs...
)
    isempty(events) && return _empty_plot("No positions"; kwargs...)

    groups = events |>
             @groupby(Dates.hour(_.open_dt)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    _with_theme() do
        plt = nothing
        for (i, (hour, group)) in enumerate(groups)
            sort!(group, by=e -> e.open_dt)
            dts = map(e -> e.open_dt, group)
            rets = map(ret_func, group)
            cum_rets = cumsum(rets)
            lbl = "$(hour):00+"
            if i == 1
                plot_kwargs = _merge_kwargs((;
                        legend=:topleft,
                        label=lbl,
                        title="Realized returns by hour",
                    ), kwargs)
                plt = Plots.plot(dts, cum_rets; plot_kwargs...)
            else
                series_kwargs = _merge_kwargs((; label=lbl), kwargs)
                Plots.plot!(plt, dts, cum_rets; series_kwargs...)
            end
            if !isempty(dts)
                Plots.annotate!(plt, dts[end], cum_rets[end],
                    Plots.text(lbl, :left, 9))
            end
        end
        plt
    end
end

"""
Plot cumulative realized returns by hour using sequence index (net, realizing trades only).
"""
function Fastback.plot_realized_cum_returns_by_hour_seq_net(trades::AbstractVector{<:Trade}; kwargs...)
    Fastback.plot_realized_cum_returns_by_hour_seq(
        trades,
        t -> realized_return(t),
        "Net realized cumulative returns by hour";
        kwargs...)
end

function Fastback.plot_realized_cum_returns_by_hour_seq_net(events::AbstractVector{<:PlotEvent}; kwargs...)
    Fastback.plot_realized_cum_returns_by_hour_seq(
        events,
        e -> e.ret,
        "Net realized cumulative returns by hour";
        kwargs...)
end

"""
Plot cumulative realized returns by hour using sequence index (gross, realizing trades only).
"""
function Fastback.plot_realized_cum_returns_by_hour_seq_gross(trades::AbstractVector{<:Trade}; kwargs...)
    Fastback.plot_realized_cum_returns_by_hour_seq(
        trades,
        t -> realized_return(t),
        "Gross realized cumulative returns by hour";
        kwargs...)
end

function Fastback.plot_realized_cum_returns_by_hour_seq_gross(events::AbstractVector{<:PlotEvent}; kwargs...)
    Fastback.plot_realized_cum_returns_by_hour_seq(
        events,
        e -> e.ret,
        "Gross realized cumulative returns by hour";
        kwargs...)
end

"""
Plot cumulative realized returns by hour using sequence index (realizing trades only).
"""
function Fastback.plot_realized_cum_returns_by_hour_seq(
    trades::AbstractVector{<:Trade},
    ret_func::Function,
    title_str::String;
    kwargs...
)
    trades = filter(is_realizing, trades)
    isempty(trades) && return _empty_plot("No realizing trades"; kwargs...)

    groups = trades |>
             @groupby(Dates.hour(_.date)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No realizing trades"; kwargs...)

    max_n = maximum(map(x -> length(x[2]), groups))
    min_date_str = Dates.format(minimum(map(t -> t.date, trades)), "yyyy/mm/dd")
    max_date_str = Dates.format(maximum(map(t -> t.date, trades)), "yyyy/mm/dd")

    _with_theme() do
        plt = nothing
        for (i, (hour, group)) in enumerate(groups)
            sort!(group, by=t -> t.date)
            rets = map(ret_func, group)
            n_pos = length(rets)
            x = collect(1:n_pos)
            cum_rets = 1.0 .+ cumsum(rets)
            lbl = "$(hour):00"
            if i == 1
                plot_kwargs = _merge_kwargs((;
                        xticks=((1, max_n), (min_date_str, max_date_str)),
                        legendfontsize=9,
                        yformatter=y -> @sprintf("%.1f", y),
                        fontsize=9,
                        w=0.5,
                        foreground_color_legend=nothing,
                        background_color_legend=nothing,
                        tickfontsize=9,
                        legend=:outertopright,
                        label=lbl,
                        title=title_str,
                    ), kwargs)
                plt = Plots.plot(x, cum_rets; plot_kwargs...)
                Plots.xlims!(plt, (1, floor(Int, 1.1 * max_n)))
            else
                series_kwargs = _merge_kwargs((; label=lbl, w=0.5), kwargs)
                Plots.plot!(plt, x, cum_rets; series_kwargs...)
            end
            if n_pos > 0
                Plots.annotate!(plt, n_pos + floor(Int, 0.03 * n_pos),
                    cum_rets[end],
                    Plots.text(lbl, :left, 8))
            end
        end
        plt
    end
end

function Fastback.plot_realized_cum_returns_by_hour_seq(
    events::AbstractVector{<:PlotEvent},
    ret_func::Function,
    title_str::String;
    kwargs...
)
    isempty(events) && return _empty_plot("No positions"; kwargs...)

    groups = events |>
             @groupby(Dates.hour(_.open_dt)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    max_n = maximum(map(x -> length(x[2]), groups))
    min_date_str = Dates.format(minimum(map(e -> e.open_dt, events)), "yyyy/mm/dd")
    max_date_str = Dates.format(maximum(map(e -> e.open_dt, events)), "yyyy/mm/dd")

    _with_theme() do
        plt = nothing
        for (i, (hour, group)) in enumerate(groups)
            sort!(group, by=e -> e.open_dt)
            rets = map(ret_func, group)
            n_pos = length(rets)
            x = collect(1:n_pos)
            cum_rets = 1.0 .+ cumsum(rets)
            lbl = "$(hour):00"
            if i == 1
                plot_kwargs = _merge_kwargs((;
                        xticks=((1, max_n), (min_date_str, max_date_str)),
                        legendfontsize=9,
                        yformatter=y -> @sprintf("%.1f", y),
                        fontsize=9,
                        w=0.5,
                        foreground_color_legend=nothing,
                        background_color_legend=nothing,
                        tickfontsize=9,
                        legend=:outertopright,
                        label=lbl,
                        title=title_str,
                    ), kwargs)
                plt = Plots.plot(x, cum_rets; plot_kwargs...)
                Plots.xlims!(plt, (1, floor(Int, 1.1 * max_n)))
            else
                series_kwargs = _merge_kwargs((; label=lbl, w=0.5), kwargs)
                Plots.plot!(plt, x, cum_rets; series_kwargs...)
            end
            if n_pos > 0
                Plots.annotate!(plt, n_pos + floor(Int, 0.03 * n_pos),
                    cum_rets[end],
                    Plots.text(lbl, :left, 8))
            end
        end
        plt
    end
end

"""
Plot cumulative realized returns grouped by weekday (realizing trades only).
"""
function Fastback.plot_realized_cum_returns_by_weekday(
    trades::AbstractVector{<:Trade},
    ret_func::Function;
    kwargs...
)
    trades = filter(is_realizing, trades)
    isempty(trades) && return _empty_plot("No realizing trades"; kwargs...)

    groups = trades |>
             @groupby(Dates.dayofweek(_.date)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No realizing trades"; kwargs...)

    max_date = maximum(map(t -> t.date, trades))
    _with_theme() do
        plt = nothing
        for (i, (weekday, group)) in enumerate(groups)
            sort!(group, by=t -> t.date)
            dts = map(t -> t.date, group)
            rets = map(ret_func, group)
            cum_rets = cumsum(rets)
            lbl = Dates.dayname(weekday)[1:3]
            if i == 1
                plot_kwargs = _merge_kwargs((;
                        legend=:topleft,
                        label=lbl,
                        title="Realized returns by weekday",
                    ), kwargs)
                plt = Plots.plot(dts, cum_rets; plot_kwargs...)
            else
                series_kwargs = _merge_kwargs((; label=lbl), kwargs)
                Plots.plot!(plt, dts, cum_rets; series_kwargs...)
            end
            if !isempty(dts)
                Plots.annotate!(plt, max_date, cum_rets[end],
                    Plots.text(lbl, :left, 8))
            end
        end
        plt
    end
end

function Fastback.plot_realized_cum_returns_by_weekday(
    events::AbstractVector{<:PlotEvent},
    ret_func::Function;
    kwargs...
)
    isempty(events) && return _empty_plot("No positions"; kwargs...)

    groups = events |>
             @groupby(Dates.dayofweek(_.open_dt)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    max_date = maximum(map(e -> e.last_dt, events))
    _with_theme() do
        plt = nothing
        for (i, (weekday, group)) in enumerate(groups)
            sort!(group, by=e -> e.open_dt)
            dts = map(e -> e.open_dt, group)
            rets = map(ret_func, group)
            cum_rets = cumsum(rets)
            lbl = Dates.dayname(weekday)[1:3]
            if i == 1
                plot_kwargs = _merge_kwargs((;
                        legend=:topleft,
                        label=lbl,
                        title="Realized returns by weekday",
                    ), kwargs)
                plt = Plots.plot(dts, cum_rets; plot_kwargs...)
            else
                series_kwargs = _merge_kwargs((; label=lbl), kwargs)
                Plots.plot!(plt, dts, cum_rets; series_kwargs...)
            end
            if !isempty(dts)
                Plots.annotate!(plt, max_date, cum_rets[end],
                    Plots.text(lbl, :left, 8))
            end
        end
        plt
    end
end

"""
Plot cumulative realized returns by weekday using sequence index (realizing trades only).
"""
function Fastback.plot_realized_cum_returns_by_weekday_seq(
    trades::AbstractVector{<:Trade},
    ret_func::Function;
    kwargs...
)
    trades = filter(is_realizing, trades)
    isempty(trades) && return _empty_plot("No realizing trades"; kwargs...)

    groups = trades |>
             @groupby(Dates.dayofweek(_.date)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No realizing trades"; kwargs...)

    _with_theme() do
        plt = nothing
        for (i, (weekday, group)) in enumerate(groups)
            sort!(group, by=t -> t.date)
            rets = map(ret_func, group)
            n_pos = length(rets)
            x = collect(1:n_pos)
            cum_rets = cumsum(rets)
            lbl = Dates.dayname(weekday)[1:3]
            if i == 1
                plot_kwargs = _merge_kwargs((;
                        legend=:bottomleft,
                        label=lbl,
                        title="Realized returns by weekday",
                    ), kwargs)
                plt = Plots.plot(x, cum_rets; plot_kwargs...)
            else
                series_kwargs = _merge_kwargs((; label=lbl), kwargs)
                Plots.plot!(plt, x, cum_rets; series_kwargs...)
            end
            if n_pos > 0
                Plots.annotate!(plt, n_pos + 1, cum_rets[end],
                    Plots.text(lbl, :left, 8))
            end
        end
        plt
    end
end

function Fastback.plot_realized_cum_returns_by_weekday_seq(
    events::AbstractVector{<:PlotEvent},
    ret_func::Function;
    kwargs...
)
    isempty(events) && return _empty_plot("No positions"; kwargs...)

    groups = events |>
             @groupby(Dates.dayofweek(_.open_dt)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    _with_theme() do
        plt = nothing
        for (i, (weekday, group)) in enumerate(groups)
            sort!(group, by=e -> e.open_dt)
            rets = map(ret_func, group)
            n_pos = length(rets)
            x = collect(1:n_pos)
            cum_rets = cumsum(rets)
            lbl = Dates.dayname(weekday)[1:3]
            if i == 1
                plot_kwargs = _merge_kwargs((;
                        legend=:bottomleft,
                        label=lbl,
                        title="Realized returns by weekday",
                    ), kwargs)
                plt = Plots.plot(x, cum_rets; plot_kwargs...)
            else
                series_kwargs = _merge_kwargs((; label=lbl), kwargs)
                Plots.plot!(plt, x, cum_rets; series_kwargs...)
            end
            if n_pos > 0
                Plots.annotate!(plt, n_pos + 1, cum_rets[end],
                    Plots.text(lbl, :left, 8))
            end
        end
        plt
    end
end


end
