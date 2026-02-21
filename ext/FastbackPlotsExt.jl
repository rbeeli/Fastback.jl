module FastbackPlotsExt

using Fastback
using Dates
using Printf
using Plots
using Query

const _HAS_STATSPLOTS = Ref(false)
const _THEME_KW = (titlelocation=:left, titlefontsize=10, widen=false, fg_legend=:false, size=(800, 450))
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
    if _HAS_STATSPLOTS[] || isdefined(Main, :StatsPlots)
        _HAS_STATSPLOTS[] = true
        return
    end
    try
        Core.eval(Main, :(import StatsPlots))
        _HAS_STATSPLOTS[] = true
        return
    catch err
        err_msg = sprint(showerror, err)
        throw(ArgumentError("StatsPlots is required for violin plots. Install it with `import Pkg; Pkg.add(\"StatsPlots\")`. Import error: $(err_msg)"))
    end
end

@inline function _with_theme(f::Function)
    Plots.with(; _THEME_KW...) do
        f()
    end
end

@inline function _empty_plot(title_text; kwargs...)
    _with_theme() do
        plot_kwargs = merge((; title=title_text), kwargs)
        Plots.plot(; plot_kwargs...)
    end
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
    plot_kwargs = merge((;
            label=label,
            linecolor=color,
            linetype=:steppost,
            yformatter=y -> @sprintf("%.0f", y),
            w=1,
        ), kwargs)
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
        Plots.scatter!(
            plt, [peak_dt], [peak_val];
            marker=:utriangle,
            markersize=4,
            color=_COLOR_DRAWDOWN,
            label=false,
        )
        Plots.scatter!(
            plt, [trough_dt], [trough_val];
            marker=:dtriangle,
            markersize=4,
            color=_COLOR_DRAWDOWN,
            label=false,
        )
        if drawdown_axis
            dd_val = _drawdown_value(peak_val, trough_val, mode)
            target = isnothing(drawdown_plot) ? plt : drawdown_plot
            Plots.scatter!(
                target, [trough_dt], [dd_val];
                marker=:circle,
                markersize=4,
                color=_COLOR_DRAWDOWN,
                label="Max drawdown",
            )
        end
    end
    plt
end

@inline function _resolve_xaxis_mode(
    dts::AbstractVector,
    vals::AbstractVector,
    xaxis_mode::Symbol,
)
    if xaxis_mode === :date
        return dts
    elseif xaxis_mode === :index
        return collect(1:length(vals))
    end
    throw(ArgumentError("xaxis_mode must be :date or :index, got $(repr(xaxis_mode))."))
end

"""
Render a title-only plot panel.
"""
function Fastback.plot_title(title_text; kwargs...)
    plot_kwargs = merge((;
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
    plt = _with_theme() do
        Plots.plot()
    end
    Fastback.plot_balance!(plt, pv; title="Balance", legend=false, kwargs...)
    plt
end

"""
Add cash balance series to an existing plot.
"""
function Fastback.plot_balance!(plt, pv::PeriodicValues; kwargs...)
    dts, vals = dates(pv), values(pv)
    isempty(vals) && return plt
    plot_kwargs = merge((;
            label="Cash balance",
            linecolor=_COLOR_BALANCE,
            linetype=:steppost,
            yformatter=y -> @sprintf("%.0f", y),
            w=1,
        ), kwargs)
    _with_theme() do
        Plots.plot!(plt, dts, vals; plot_kwargs...)
    end
    plt
end

"""
Plot equity from `PeriodicValues`.

Use `xaxis_mode=:date` (default) or `xaxis_mode=:index`.
"""
function Fastback.plot_equity(pv::PeriodicValues; xaxis_mode::Symbol=:date, kwargs...)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No equity data"; kwargs...)
    plt = _with_theme() do
        Plots.plot()
    end
    Fastback.plot_equity!(plt, pv; xaxis_mode=xaxis_mode, title="Equity", legend=false, kwargs...)
    plt
end

"""
Add equity series to an existing plot.
"""
function Fastback.plot_equity!(plt, pv::PeriodicValues; xaxis_mode::Symbol=:date, kwargs...)
    dts, vals = dates(pv), values(pv)
    isempty(vals) && return plt
    x = _resolve_xaxis_mode(dts, vals, xaxis_mode)
    plot_kwargs = merge((;
            label="Equity",
            linecolor=_COLOR_EQUITY,
            linetype=:steppost,
            yformatter=y -> @sprintf("%.0f", y),
            w=1,
        ), kwargs)
    _with_theme() do
        Plots.plot!(plt, x, vals; plot_kwargs...)
    end
    plt
end

"""
Plot open orders from `PeriodicValues`.

Use `xaxis_mode=:date` (default) or `xaxis_mode=:index`.
"""
function Fastback.plot_open_orders_count(pv::PeriodicValues; xaxis_mode::Symbol=:date, kwargs...)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No open orders data"; kwargs...)
    plt = _with_theme() do
        Plots.plot()
    end
    Fastback.plot_open_orders_count!(plt, pv; xaxis_mode=xaxis_mode, title="# open orders", legend=false, kwargs...)
    plt
end

"""
Add open orders series to an existing plot.
"""
function Fastback.plot_open_orders_count!(plt, pv::PeriodicValues; xaxis_mode::Symbol=:date, kwargs...)
    dts, vals = dates(pv), values(pv)
    isempty(vals) && return plt
    x = _resolve_xaxis_mode(dts, vals, xaxis_mode)
    max_open = maximum(vals)
    max_tick = max(0, floor(Int, max_open))
    y_ticks = 0:max_tick
    y_ticks_str = map(x -> @sprintf("%.0f", x), y_ticks)
    plot_kwargs = merge((;
            label="# open orders",
            linecolor=_COLOR_OPEN_ORDERS,
            linetype=:steppost,
            yticks=(y_ticks, y_ticks_str),
            legend=false,
        ), kwargs)
    _with_theme() do
        Plots.plot!(plt, x, vals; plot_kwargs...)
        Plots.ylims!(plt, (0, max(0, max_open)))
    end
    plt
end

@inline function _drawdown_kwargs(pv::DrawdownValues)
    if pv.mode == DrawdownMode.Percentage
        return (;
            label="Drawdown",
            fill=(0, _FILL_DRAWDOWN),
            linecolor=_COLOR_DRAWDOWN,
            linetype=:steppost,
            yformatter=y -> @sprintf("%.1f%%", 100y),
            ylims=(-1.0, 0.0),
            w=1,
            legend=false,
        )
    end
    (;
        label="Drawdown",
        fill=(0, _FILL_DRAWDOWN),
        linecolor=_COLOR_DRAWDOWN,
        linetype=:steppost,
        yformatter=y -> @sprintf("%.0f", y),
        w=1,
        legend=false,
    )
end

"""
Plot drawdown series from `DrawdownValues`.
"""
function Fastback.plot_drawdown(pv::DrawdownValues; xaxis_mode::Symbol=:date, kwargs...)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No drawdown data"; kwargs...)
    title = (pv.mode == DrawdownMode.Percentage ? "Equity drawdowns [%]" : "Equity drawdowns")
    plt = _with_theme() do
        Plots.plot()
    end
    Fastback.plot_drawdown!(plt, pv; xaxis_mode=xaxis_mode, title=title, legend=false, kwargs...)
    plt
end

"""
Add drawdown series to an existing plot.
"""
function Fastback.plot_drawdown!(plt, pv::DrawdownValues; xaxis_mode::Symbol=:date, kwargs...)
    dts, vals = dates(pv), values(pv)
    isempty(vals) && return plt
    x = _resolve_xaxis_mode(dts, vals, xaxis_mode)
    plot_kwargs = merge(_drawdown_kwargs(pv), kwargs)
    _with_theme() do
        Plots.plot!(plt, x, vals; plot_kwargs...)
    end
    plt
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
    plt = _with_theme() do
        Plots.plot()
    end
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

    eq_kwargs = merge((;
            ylabel="Equity",
            z_order=:front,
        ), kwargs)
    Fastback.plot_equity!(plt, equity_pv; eq_kwargs...)

    dd_vals = values(drawdown_pv)
    dd_plot = nothing
    if !isempty(dd_vals)
        legend_val = haskey(kwargs, :legend) ? kwargs[:legend] : :topleft
        dd_kwargs = merge(_drawdown_kwargs(drawdown_pv), (;
            ylabel=_drawdown_axis_label(drawdown_pv),
            legend=legend_val,
            linealpha=0.45,
            z_order=:back,
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
    plt = _with_theme() do
        Plots.plot()
    end
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
    plot_kwargs = merge((;
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
    theme_width, theme_height = _THEME_KW.size
    plot_kwargs = merge((;
            layout=(length(kinds), 1),
            size=(theme_width, theme_height * length(kinds)),
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

Use `return_basis=:gross` (default) or `return_basis=:net`.
`NaN` return values are ignored.
"""
function Fastback.plot_violin_realized_returns_by_day(
    trades::AbstractVector{<:Trade};
    return_basis::Symbol=:gross,
    kwargs...
)
    _ensure_statsplots()
    ret_func, basis_label = _resolve_return_basis(return_basis)
    trades = filter(is_realizing, trades)
    isempty(trades) && return _empty_plot("No realizing trades"; kwargs...)

    groups = trades |>
             @groupby(Dates.dayofweek(_.date)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No realizing trades"; kwargs...)

    y = Vector{Vector{Float64}}()
    x_lbls = String[]
    for (day, group) in groups
        vals = _collect_non_nan_rets(group, ret_func)
        isempty(vals) && continue
        push!(y, vals)
        push!(x_lbls, Dates.dayname(day))
    end
    isempty(y) && return _empty_plot("No realizing trades"; kwargs...)

    plot_kwargs = merge((;
            xticks=(1:length(y), x_lbls),
            fill="green",
            linewidth=0,
            title="$(basis_label) realized returns by day (trade date)",
            legend=false,
        ), kwargs)
    _with_theme() do
        sp = Base.invokelatest(getfield, Main, :StatsPlots)
        Base.invokelatest(sp.violin, y; plot_kwargs...)
    end
end

"""
Violin plot of realized returns grouped by hour (realizing trades only).

Use `return_basis=:gross` (default) or `return_basis=:net`.
`NaN` return values are ignored.
"""
function Fastback.plot_violin_realized_returns_by_hour(
    trades::AbstractVector{<:Trade};
    return_basis::Symbol=:gross,
    kwargs...
)
    _ensure_statsplots()
    ret_func, basis_label = _resolve_return_basis(return_basis)
    trades = filter(is_realizing, trades)
    isempty(trades) && return _empty_plot("No realizing trades"; kwargs...)

    groups = trades |>
             @groupby(Dates.hour(_.date)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No realizing trades"; kwargs...)

    y = Vector{Vector{Float64}}()
    x_lbls = String[]
    for (hour, group) in groups
        vals = _collect_non_nan_rets(group, ret_func)
        isempty(vals) && continue
        push!(y, vals)
        push!(x_lbls, string(hour))
    end
    isempty(y) && return _empty_plot("No realizing trades"; kwargs...)

    plot_kwargs = merge((;
            xticks=(1:length(y), x_lbls),
            fill="green",
            linewidth=0,
            title="$(basis_label) realized returns by hour (trade time)",
            legend=false,
        ), kwargs)
    _with_theme() do
        sp = Base.invokelatest(getfield, Main, :StatsPlots)
        Base.invokelatest(sp.violin, y; plot_kwargs...)
    end
end

"""
Plot cumulative realized returns grouped by hour (realizing trades only).

Use `return_basis=:gross` (default) or `return_basis=:net`.
Use `xaxis_mode=:date` (default) or `xaxis_mode=:index`.
`NaN` return values are ignored.
"""
function Fastback.plot_realized_cum_returns_by_hour(
    trades::AbstractVector{<:Trade};
    return_basis::Symbol=:gross,
    xaxis_mode::Symbol=:date,
    kwargs...
)
    ret_func, basis_label = _resolve_return_basis(return_basis)
    index_axis = if xaxis_mode === :date
        false
    elseif xaxis_mode === :index
        true
    else
        throw(ArgumentError("xaxis_mode must be :date or :index, got $(repr(xaxis_mode))."))
    end
    title_str = if index_axis
        "$(basis_label) realized cumulative returns by hour"
    else
        "$(basis_label) realized returns by hour"
    end
    trades = filter(is_realizing, trades)
    isempty(trades) && return _empty_plot("No realizing trades"; kwargs...)

    groups = trades |>
             @groupby(Dates.hour(_.date)) |>
             @orderby(key(_)) |>
             @map(key(_) => collect(_)) |>
             collect
    isempty(groups) && return _empty_plot("No realizing trades"; kwargs...)

    max_n = 0
    min_date_str = ""
    max_date_str = ""
    if index_axis
        max_n = maximum(map(x -> length(x[2]), groups))
        min_date_str = Dates.format(minimum(map(t -> t.date, trades)), "yyyy/mm/dd")
        max_date_str = Dates.format(maximum(map(t -> t.date, trades)), "yyyy/mm/dd")
    end

    _with_theme() do
        plt = nothing
        for (hour, group) in groups
            sort!(group, by=t -> t.date)
            if index_axis
                rets = _collect_non_nan_rets(group, ret_func)
                isempty(rets) && continue
                n_pos = length(rets)
                x = collect(1:n_pos)
                cum_rets = 1.0 .+ cumsum(rets)
                lbl = "$(hour):00"
                if plt === nothing
                    plot_kwargs = merge((;
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
                    series_kwargs = merge((; label=lbl, w=0.5), kwargs)
                    Plots.plot!(plt, x, cum_rets; series_kwargs...)
                end
                if n_pos > 0
                    lbl_color = get(plt.series_list[end].plotattributes, :seriescolor, :white)
                    Plots.annotate!(plt, n_pos + floor(Int, 0.03 * n_pos),
                        cum_rets[end],
                        Plots.text(lbl, :left, 8, lbl_color))
                end
            else
                dts, rets = _collect_non_nan_dts_rets(group, t -> t.date, ret_func)
                isempty(rets) && continue
                cum_rets = cumsum(rets)
                lbl = "$(hour):00+"
                if plt === nothing
                    plot_kwargs = merge((;
                            legend=:topleft,
                            label=lbl,
                            title=title_str,
                        ), kwargs)
                    plt = Plots.plot(dts, cum_rets; plot_kwargs...)
                else
                    series_kwargs = merge((; label=lbl), kwargs)
                    Plots.plot!(plt, dts, cum_rets; series_kwargs...)
                end
                if !isempty(dts)
                    lbl_color = get(plt.series_list[end].plotattributes, :seriescolor, :white)
                    Plots.annotate!(plt, dts[end], cum_rets[end],
                        Plots.text(lbl, :left, 9, lbl_color))
                end
            end
        end
        plt === nothing ? _empty_plot("No realizing trades"; kwargs...) : plt
    end
end

@inline function _resolve_return_basis(return_basis::Symbol)
    if return_basis === :gross
        return realized_return_gross, "Gross"
    elseif return_basis === :net
        return realized_return_net, "Net"
    end
    throw(ArgumentError("return_basis must be :gross or :net, got $(repr(return_basis))."))
end

@inline function _collect_non_nan_dts_rets(group, dt_func::Function, ret_func::Function)
    dts = typeof(dt_func(first(group)))[]
    rets = Float64[]
    for item in group
        ret = ret_func(item)
        isnan(ret) && continue
        push!(dts, dt_func(item))
        push!(rets, Float64(ret))
    end
    dts, rets
end

@inline function _collect_non_nan_rets(group, ret_func::Function)
    rets = Float64[]
    for item in group
        ret = ret_func(item)
        isnan(ret) && continue
        push!(rets, Float64(ret))
    end
    rets
end

"""
Plot cumulative realized returns grouped by weekday (realizing trades only).

Use `return_basis=:gross` (default) or `return_basis=:net`.
Use `xaxis_mode=:date` (default) or `xaxis_mode=:index`.
`NaN` return values are ignored.
"""
function Fastback.plot_realized_cum_returns_by_weekday(
    trades::AbstractVector{<:Trade},
    ;
    return_basis::Symbol=:gross,
    xaxis_mode::Symbol=:date,
    kwargs...
)
    ret_func, basis_label = _resolve_return_basis(return_basis)
    index_axis = if xaxis_mode === :date
        false
    elseif xaxis_mode === :index
        true
    else
        throw(ArgumentError("xaxis_mode must be :date or :index, got $(repr(xaxis_mode))."))
    end
    title_str = "$(basis_label) realized returns by weekday"
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
        for (weekday, group) in groups
            sort!(group, by=t -> t.date)
            lbl = Dates.dayname(weekday)[1:3]
            if index_axis
                rets = _collect_non_nan_rets(group, ret_func)
                isempty(rets) && continue
                n_pos = length(rets)
                x = collect(1:n_pos)
                cum_rets = cumsum(rets)
                if plt === nothing
                    plot_kwargs = merge((;
                            legend=:bottomleft,
                            label=lbl,
                            title=title_str,
                        ), kwargs)
                    plt = Plots.plot(x, cum_rets; plot_kwargs...)
                else
                    series_kwargs = merge((; label=lbl), kwargs)
                    Plots.plot!(plt, x, cum_rets; series_kwargs...)
                end
                if n_pos > 0
                    lbl_color = get(plt.series_list[end].plotattributes, :seriescolor, :white)
                    Plots.annotate!(plt, n_pos + 1, cum_rets[end],
                        Plots.text(lbl, :left, 8, lbl_color))
                end
            else
                dts, rets = _collect_non_nan_dts_rets(group, t -> t.date, ret_func)
                isempty(rets) && continue
                cum_rets = cumsum(rets)
                if plt === nothing
                    plot_kwargs = merge((;
                            legend=:topleft,
                            label=lbl,
                            title=title_str,
                        ), kwargs)
                    plt = Plots.plot(dts, cum_rets; plot_kwargs...)
                else
                    series_kwargs = merge((; label=lbl), kwargs)
                    Plots.plot!(plt, dts, cum_rets; series_kwargs...)
                end
                if !isempty(dts)
                    lbl_color = get(plt.series_list[end].plotattributes, :seriescolor, :white)
                    Plots.annotate!(plt, dts[end], cum_rets[end],
                        Plots.text(lbl, :left, 8, lbl_color))
                end
            end
        end
        plt === nothing ? _empty_plot("No realizing trades"; kwargs...) : plt
    end
end

end
