module FastbackPlotsExt

using Fastback
using Dates
using Printf
using Plots
using Query

const _THEME_KW = (
    titlelocation=:left,
    titlefontsize=10,
    widen=true,
    fg_legend=false,
    size=(800, 450),
    background_color=Fastback._PLOT_COLORS.canvas,
    foreground_color=Fastback._PLOT_COLORS.text,
    foreground_color_axis=Fastback._PLOT_COLORS.axis,
    foreground_color_text=Fastback._PLOT_COLORS.muted,
    foreground_color_guide=Fastback._PLOT_COLORS.muted,
    color_palette=collect(Fastback._PLOT_PALETTE),
    grid=false,
)

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
    color
    ;
    kwargs...,
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

function _add_max_drawdown_markers!(
    plt,
    dts::AbstractVector{<:Dates.AbstractTime},
    vals::AbstractVector{<:Real},
    mode::DrawdownMode.T
    ;
    drawdown_axis::Bool=true,
    drawdown_plot=nothing,
)
    peak_idx, trough_idx, max_dd = Fastback._plot_max_drawdown_indices(vals, mode)
    max_dd < 0 || return plt
    peak_dt, trough_dt = dts[peak_idx], dts[trough_idx]
    peak_val, trough_val = vals[peak_idx], vals[trough_idx]
    _with_theme() do
        Plots.scatter!(
            plt, [peak_dt], [peak_val];
            marker=:utriangle,
            markersize=4,
            color=Fastback._PLOT_COLORS.drawdown,
            label=false,
        )
        Plots.scatter!(
            plt, [trough_dt], [trough_val];
            marker=:dtriangle,
            markersize=4,
            color=Fastback._PLOT_COLORS.drawdown,
            label=false,
        )
        if drawdown_axis
            dd_val = Fastback._plot_drawdown_value(peak_val, trough_val, mode)
            target = isnothing(drawdown_plot) ? plt : drawdown_plot
            Plots.scatter!(
                target, [trough_dt], [dd_val];
                marker=:circle,
                markersize=4,
                color=Fastback._PLOT_COLORS.drawdown,
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
function Fastback.plot_title(backend::Fastback.PlotsBackend, title_text; kwargs...)
    plot_kwargs = merge((;
            marker=0,
            markeralpha=0,
            annotations=(1.5, 1.5, title_text),
            foreground_color_subplot=Fastback._PLOT_COLORS.text,
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
function Fastback.plot_balance(backend::Fastback.PlotsBackend, pv::PeriodicValues; kwargs...)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No balance data"; kwargs...)
    plt = _with_theme() do
        Plots.plot()
    end
    Fastback.plot_balance!(backend, plt, pv; title="Balance", legend=false, kwargs...)
    plt
end

"""
Add cash balance series to an existing plot.
"""
function Fastback.plot_balance!(
    backend::Fastback.PlotsBackend,
    plt::Plots.Plot,
    pv::PeriodicValues
    ;
    kwargs...,
)
    dts, vals = dates(pv), values(pv)
    isempty(vals) && return plt
    plot_kwargs = merge((;
            label="Cash balance",
            linecolor=Fastback._PLOT_COLORS.balance,
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
function Fastback.plot_equity(
    backend::Fastback.PlotsBackend,
    pv::PeriodicValues
    ;
    xaxis_mode::Symbol=:date,
    kwargs...,
)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No equity data"; kwargs...)
    plt = _with_theme() do
        Plots.plot()
    end
    Fastback.plot_equity!(backend, plt, pv; xaxis_mode=xaxis_mode, title="Equity", legend=false, kwargs...)
    plt
end

"""
Add equity series to an existing plot.
"""
function Fastback.plot_equity!(
    backend::Fastback.PlotsBackend,
    plt::Plots.Plot,
    pv::PeriodicValues
    ;
    xaxis_mode::Symbol=:date,
    kwargs...,
)
    dts, vals = dates(pv), values(pv)
    isempty(vals) && return plt
    x = _resolve_xaxis_mode(dts, vals, xaxis_mode)
    plot_kwargs = merge((;
            label="Equity",
            linecolor=Fastback._PLOT_COLORS.equity,
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
function Fastback.plot_open_orders_count(
    backend::Fastback.PlotsBackend,
    pv::PeriodicValues
    ;
    xaxis_mode::Symbol=:date,
    kwargs...,
)
    plt = _with_theme() do
        Plots.plot()
    end
    Fastback.plot_open_orders_count!(backend, plt, pv; xaxis_mode=xaxis_mode, title="Open orders count", legend=false, kwargs...)
    plt
end

"""
Add open orders series to an existing plot.
"""
function Fastback.plot_open_orders_count!(
    backend::Fastback.PlotsBackend,
    plt::Plots.Plot,
    pv::PeriodicValues
    ;
    xaxis_mode::Symbol=:date,
    ylims=nothing,
    kwargs...,
)
    dts, vals = dates(pv), values(pv)
    x = _resolve_xaxis_mode(dts, vals, xaxis_mode)
    bounds, y_ticks = Fastback._plot_count_axis(vals; ylims)
    y_ticks_str = map(x -> @sprintf("%.0f", x), y_ticks)
    plot_kwargs = merge((;
            label="Open orders count",
            linecolor=Fastback._PLOT_COLORS.open_orders,
            linetype=:steppost,
            yticks=(y_ticks, y_ticks_str),
            ylims=bounds,
            legend=false,
        ), kwargs)
    _with_theme() do
        Plots.plot!(plt, x, vals; plot_kwargs...)
    end
    plt
end

@inline function _drawdown_kwargs(pv::DrawdownValues)
    if pv.mode == DrawdownMode.Percentage
        return (;
            label="Drawdown",
            fillrange=0,
            fillcolor=Fastback._PLOT_COLORS.drawdown,
            fillalpha=0.3,
            linecolor=Fastback._PLOT_COLORS.drawdown,
            linetype=:steppost,
            yformatter=y -> @sprintf("%.1f%%", 100y),
            ylims=(-1.0, 0.0),
            w=1,
            legend=false,
        )
    end
    (;
        label="Drawdown",
        fillrange=0,
        fillcolor=Fastback._PLOT_COLORS.drawdown,
        fillalpha=0.3,
        linecolor=Fastback._PLOT_COLORS.drawdown,
        linetype=:steppost,
        yformatter=y -> @sprintf("%.0f", y),
        w=1,
        legend=false,
    )
end

"""
Plot drawdown series from `DrawdownValues`.
"""
function Fastback.plot_drawdown(
    backend::Fastback.PlotsBackend,
    pv::DrawdownValues
    ;
    xaxis_mode::Symbol=:date,
    kwargs...,
)
    vals = values(pv)
    isempty(vals) && return _empty_plot("No drawdown data"; kwargs...)
    title = (pv.mode == DrawdownMode.Percentage ? "Equity drawdowns [%]" : "Equity drawdowns")
    plt = _with_theme() do
        Plots.plot()
    end
    Fastback.plot_drawdown!(backend, plt, pv; xaxis_mode=xaxis_mode, title=title, legend=false, kwargs...)
    plt
end

"""
Add drawdown series to an existing plot.
"""
function Fastback.plot_drawdown!(
    backend::Fastback.PlotsBackend,
    plt::Plots.Plot,
    pv::DrawdownValues
    ;
    xaxis_mode::Symbol=:date,
    kwargs...,
)
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
    backend::Fastback.PlotsBackend,
    equity_pv::PeriodicValues,
    drawdown_pv::DrawdownValues
    ;
    show_max_dd::Bool=true,
    kwargs...,
)
    eq_vals = values(equity_pv)
    isempty(eq_vals) && return _empty_plot("No equity data"; kwargs...)
    plt = _with_theme() do
        Plots.plot()
    end
    Fastback.plot_equity_drawdown!(backend, plt, equity_pv, drawdown_pv;
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
    backend::Fastback.PlotsBackend,
    plt::Plots.Plot,
    equity_pv::PeriodicValues,
    drawdown_pv::DrawdownValues
    ;
    show_max_dd::Bool=true,
    kwargs...,
)
    eq_vals = values(equity_pv)
    isempty(eq_vals) && return plt

    eq_kwargs = merge((;
            ylabel="Equity",
            z_order=:front,
        ), kwargs)
    Fastback.plot_equity!(backend, plt, equity_pv; eq_kwargs...)

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
function Fastback.plot_exposure(
    backend::Fastback.PlotsBackend
    ;
    gross=nothing,
    net=nothing,
    long=nothing,
    short=nothing,
    kwargs...,
)
    has_data = _has_values(gross) || _has_values(net) || _has_values(long) || _has_values(short)
    has_data || return _empty_plot("No exposure data"; kwargs...)
    plt = _with_theme() do
        Plots.plot()
    end
    Fastback.plot_exposure!(backend, plt;
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
    backend::Fastback.PlotsBackend,
    plt::Plots.Plot
    ;
    gross=nothing,
    net=nothing,
    long=nothing,
    short=nothing,
    kwargs...,
)
    _with_theme() do
        _plot_exposure_series!(plt, gross, "Gross exposure", Fastback._PLOT_COLORS.exposure_gross; kwargs...)
        _plot_exposure_series!(plt, net, "Net exposure", Fastback._PLOT_COLORS.exposure_net; kwargs...)
        _plot_exposure_series!(plt, long, "Long exposure", Fastback._PLOT_COLORS.exposure_long; kwargs...)
        _plot_exposure_series!(plt, short, "Short exposure", Fastback._PLOT_COLORS.exposure_short; kwargs...)
    end
    plt
end

"""
Plot portfolio constituent weights over time as a stacked area chart.

`weights` must be shaped as `(length(dts), length(symbols))`.
"""
function Fastback.plot_portfolio_weights_over_time(
    backend::Fastback.PlotsBackend,
    dts::AbstractVector{<:Dates.AbstractTime},
    weights::AbstractMatrix{<:Real},
    symbols::AbstractVector
    ;
    kwargs...,
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
    backend::Fastback.PlotsBackend,
    pv::PortfolioWeightsValues
    ;
    kwargs...,
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
    Fastback.plot_portfolio_weights_over_time(backend, dts, weights, symbols; kwargs...)
end

"""
Plot account cashflows by type (one panel per `CashflowKind`).
"""
function Fastback.plot_cashflows(backend::Fastback.PlotsBackend, acc::Account{TTime}; kwargs...) where {TTime<:Dates.AbstractTime}
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
            Plots.hline!(p[i], [0.0]; color=Fastback._PLOT_COLORS.axis, alpha=0.2)
        end
        p
    end
end

"""
Plot cumulative realized returns grouped by hour (realizing trades only).

Use `return_basis=:gross` (default) or `return_basis=:net`.
Use `xaxis_mode=:date` (default) or `xaxis_mode=:index`.
`NaN` return values are ignored.

Returns are aggregated per timestamp using realized-notional weights, then
compounded over time (`cumprod(1 + r) - 1`).
"""
function Fastback.plot_realized_cum_returns_by_hour(
    backend::Fastback.PlotsBackend,
    trades::AbstractVector{<:Trade}
    ;
    return_basis::Symbol=:gross,
    xaxis_mode::Symbol=:date,
    kwargs...,
)
    ret_func, basis_label = _resolve_return_basis(return_basis)
    index_axis = if xaxis_mode === :date
        false
    elseif xaxis_mode === :index
        true
    else
        throw(ArgumentError("xaxis_mode must be :date or :index, got $(repr(xaxis_mode))."))
    end
    title_str = "$(basis_label) realized cumulative returns by hour"
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
        min_dt = nothing
        max_dt = nothing
        for (_, group) in groups
            sort!(group, by=t -> t.date)
            dts, rets = _collect_weighted_dts_rets(group, t -> t.date, ret_func)
            isempty(rets) && continue
            max_n = max(max_n, length(rets))
            min_dt = isnothing(min_dt) ? dts[1] : min(min_dt, dts[1])
            max_dt = isnothing(max_dt) ? dts[end] : max(max_dt, dts[end])
        end
        max_n == 0 && return _empty_plot("No realizing trades"; kwargs...)
        min_date_str = Dates.format(min_dt, "yyyy/mm/dd")
        max_date_str = Dates.format(max_dt, "yyyy/mm/dd")
    end

    _with_theme() do
        plt = nothing
        for (hour, group) in groups
            sort!(group, by=t -> t.date)
            dts, rets = _collect_weighted_dts_rets(group, t -> t.date, ret_func)
            isempty(rets) && continue
            cum_rets = _compounded_cum_returns(rets)
            if index_axis
                n_pos = length(rets)
                x = collect(1:n_pos)
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
                            legend=false,
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
                    lbl_color = get(plt.series_list[end].plotattributes, :seriescolor, Fastback._PLOT_COLORS.text)
                    Plots.annotate!(plt, n_pos + floor(Int, 0.03 * n_pos),
                        cum_rets[end],
                        Plots.text(lbl, :left, 8, lbl_color))
                end
            else
                lbl = "$(hour):00+"
                if plt === nothing
                    plot_kwargs = merge((;
                            legend=false,
                            label=lbl,
                            title=title_str,
                        ), kwargs)
                    plt = Plots.plot(dts, cum_rets; plot_kwargs...)
                else
                    series_kwargs = merge((; label=lbl), kwargs)
                    Plots.plot!(plt, dts, cum_rets; series_kwargs...)
                end
                if !isempty(dts)
                    lbl_color = get(plt.series_list[end].plotattributes, :seriescolor, Fastback._PLOT_COLORS.text)
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

@inline function _collect_weighted_dts_rets(group, dt_func::Function, ret_func::Function)
    dts = typeof(dt_func(first(group)))[]
    rets = Float64[]
    num = 0.0
    den = 0.0
    have_bucket = false
    bucket_dt = dt_func(first(group))

    for item in group
        ret = ret_func(item)
        isnan(ret) && continue

        realized_notional = realized_notional_quote(item)
        (!isfinite(realized_notional) || realized_notional <= 0.0) && continue

        dt = dt_func(item)
        if !have_bucket
            bucket_dt = dt
            have_bucket = true
        elseif dt != bucket_dt
            if den > 0.0
                push!(dts, bucket_dt)
                push!(rets, num / den)
            end
            bucket_dt = dt
            num = 0.0
            den = 0.0
        end

        num += Float64(ret) * realized_notional
        den += realized_notional
    end

    if have_bucket && den > 0.0
        push!(dts, bucket_dt)
        push!(rets, num / den)
    end

    dts, rets
end

@inline function _compounded_cum_returns(rets::AbstractVector{<:Real})
    n = length(rets)
    n == 0 && return Float64[]
    out = Vector{Float64}(undef, n)
    growth = 1.0
    @inbounds for i in eachindex(rets)
        growth *= 1.0 + Float64(rets[i])
        out[i] = growth - 1.0
    end
    out
end

"""
Plot cumulative realized returns grouped by weekday (realizing trades only).

Use `return_basis=:gross` (default) or `return_basis=:net`.
Use `xaxis_mode=:date` (default) or `xaxis_mode=:index`.
`NaN` return values are ignored.

Returns are aggregated per timestamp using realized-notional weights, then
compounded over time (`cumprod(1 + r) - 1`).
"""
function Fastback.plot_realized_cum_returns_by_weekday(
    backend::Fastback.PlotsBackend,
    trades::AbstractVector{<:Trade}
    ;
    return_basis::Symbol=:gross,
    xaxis_mode::Symbol=:date,
    kwargs...,
)
    ret_func, basis_label = _resolve_return_basis(return_basis)
    index_axis = if xaxis_mode === :date
        false
    elseif xaxis_mode === :index
        true
    else
        throw(ArgumentError("xaxis_mode must be :date or :index, got $(repr(xaxis_mode))."))
    end
    title_str = "$(basis_label) realized cumulative returns by weekday"
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
            dts, rets = _collect_weighted_dts_rets(group, t -> t.date, ret_func)
            isempty(rets) && continue
            cum_rets = _compounded_cum_returns(rets)
            lbl = Dates.dayname(weekday)[1:3]
            if index_axis
                n_pos = length(rets)
                x = collect(1:n_pos)
                if plt === nothing
                    plot_kwargs = merge((;
                            legend=false,
                            label=lbl,
                            title=title_str,
                        ), kwargs)
                    plt = Plots.plot(x, cum_rets; plot_kwargs...)
                else
                    series_kwargs = merge((; label=lbl), kwargs)
                    Plots.plot!(plt, x, cum_rets; series_kwargs...)
                end
                if n_pos > 0
                    lbl_color = get(plt.series_list[end].plotattributes, :seriescolor, Fastback._PLOT_COLORS.text)
                    Plots.annotate!(plt, n_pos + 1, cum_rets[end],
                        Plots.text(lbl, :left, 8, lbl_color))
                end
            else
                if plt === nothing
                    plot_kwargs = merge((;
                            legend=false,
                            label=lbl,
                            title=title_str,
                        ), kwargs)
                    plt = Plots.plot(dts, cum_rets; plot_kwargs...)
                else
                    series_kwargs = merge((; label=lbl), kwargs)
                    Plots.plot!(plt, dts, cum_rets; series_kwargs...)
                end
                if !isempty(dts)
                    lbl_color = get(plt.series_list[end].plotattributes, :seriescolor, Fastback._PLOT_COLORS.text)
                    Plots.annotate!(plt, dts[end], cum_rets[end],
                        Plots.text(lbl, :left, 8, lbl_color))
                end
            end
        end
        plt === nothing ? _empty_plot("No realizing trades"; kwargs...) : plt
    end
end

end
