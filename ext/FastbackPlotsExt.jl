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
const _COLOR_DRAWDOWN = "#BB0000"
const _FILL_DRAWDOWN = "#BB000033"

@inline function _ensure_statsplots()
    if _HAS_STATSPLOTS[]
        return true
    end
    try
        @eval import StatsPlots
        _HAS_STATSPLOTS[] = true
        return true
    catch
        return false
    end
end

@inline _fmt0(x) = @sprintf("%.0f", x)
@inline _fmt1(x) = @sprintf("%.1f", x)
@inline _merge_kwargs(defaults::NamedTuple, kwargs) = merge(defaults, (; kwargs...))
@inline function _empty_plot(title_text; kwargs...)
    plot_kwargs = _merge_kwargs((; _THEME_KW..., title=title_text), kwargs)
    Plots.plot(; plot_kwargs...)
end

@inline function _series_data(pv)
    dts = dates(pv)
    vals = values(pv)
    return dts, vals
end

struct PlotEvent{TTime<:Dates.AbstractTime}
    open_dt::TTime
    last_dt::TTime
    ret::Float64
end

@inline PlotEvent(open_dt::TTime, last_dt::TTime, ret::Real) where {TTime<:Dates.AbstractTime} =
    PlotEvent{TTime}(open_dt, last_dt, Float64(ret))

@inline PlotEvent(t::Trade{T}) where {T<:Dates.AbstractTime} =
    PlotEvent{T}(t.date, t.date, realized_return(t; zero_value=0.0))

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
    Plots.scatter(1:2; plot_kwargs...)
end

function Fastback.plot_balance(pv::PeriodicValues; kwargs...)
    dts, vals = _series_data(pv)
    isempty(vals) && return _empty_plot("No balance data"; kwargs...)
    plot_kwargs = _merge_kwargs((;
        _THEME_KW...,
        fontfamily="Computer Modern",
        title="Balance",
        linecolor=_COLOR_BALANCE,
        linetype=:steppost,
        yformatter=_fmt0,
        w=1,
        legend=false,
    ), kwargs)
    plt = Plots.plot(dts, vals; plot_kwargs...)
    Plots.ylims!(plt, (0, maximum(vals)))
    plt
end

function Fastback.plot_equity(pv::PeriodicValues; kwargs...)
    dts, vals = _series_data(pv)
    isempty(vals) && return _empty_plot("No equity data"; kwargs...)
    plot_kwargs = _merge_kwargs((;
        _THEME_KW...,
        fontfamily="Computer Modern",
        title="Equity",
        linecolor=_COLOR_EQUITY,
        linetype=:steppost,
        yformatter=_fmt0,
        w=1,
        legend=false,
    ), kwargs)
    Plots.plot(dts, vals; plot_kwargs...)
end

function Fastback.plot_equity_seq(pv::PeriodicValues; kwargs...)
    _, vals = _series_data(pv)
    isempty(vals) && return _empty_plot("No equity data"; kwargs...)
    x = collect(1:length(vals))
    plot_kwargs = _merge_kwargs((;
        _THEME_KW...,
        fontfamily="Computer Modern",
        title="Equity",
        linecolor=_COLOR_EQUITY,
        linetype=:steppost,
        yformatter=_fmt0,
        w=1,
        legend=false,
    ), kwargs)
    Plots.plot(x, vals; plot_kwargs...)
end

function Fastback.plot_open_orders(pv::PeriodicValues; kwargs...)
    dts, vals = _series_data(pv)
    isempty(vals) && return _empty_plot("No open orders data"; kwargs...)
    max_open = maximum(vals)
    max_tick = max(0, floor(Int, max_open))
    y_ticks = 0:max_tick
    y_ticks_str = map(_fmt0, y_ticks)

    plot_kwargs = _merge_kwargs((;
        _THEME_KW...,
        fontfamily="Computer Modern",
        title="# open orders",
        color="black",
        linetype=:steppost,
        yticks=(y_ticks, y_ticks_str),
        legend=false,
    ), kwargs)
    plt = Plots.plot(dts, vals; plot_kwargs...)
    Plots.ylims!(plt, (0, max(0, max_open)))
    plt
end

function Fastback.plot_open_orders_seq(pv::PeriodicValues; kwargs...)
    _, vals = _series_data(pv)
    isempty(vals) && return _empty_plot("No open orders data"; kwargs...)
    x = collect(1:length(vals))
    max_open = maximum(vals)
    max_tick = max(0, floor(Int, max_open))
    y_ticks = 0:max_tick
    y_ticks_str = map(_fmt0, y_ticks)

    plot_kwargs = _merge_kwargs((;
        _THEME_KW...,
        fontfamily="Computer Modern",
        title="# open orders",
        color="black",
        linetype=:steppost,
        yticks=(y_ticks, y_ticks_str),
        legend=false,
    ), kwargs)
    plt = Plots.plot(x, vals; plot_kwargs...)
    Plots.ylims!(plt, (0, max(0, max_open)))
    plt
end

function Fastback.plot_drawdown(pv::DrawdownValues; kwargs...)
    dts, vals = _series_data(pv)
    isempty(vals) && return _empty_plot("No drawdown data"; kwargs...)
    plot_kwargs = _merge_kwargs((;
        _THEME_KW...,
        fontfamily="Computer Modern",
        title="Drawdown",
        fill=(0, _FILL_DRAWDOWN),
        linecolor=_COLOR_DRAWDOWN,
        linetype=:steppost,
        yformatter=_fmt0,
        w=1,
        legend=false,
    ), kwargs)
    Plots.plot(dts, vals; plot_kwargs...)
end

function Fastback.plot_drawdown_seq(pv::DrawdownValues; kwargs...)
    _, vals = _series_data(pv)
    isempty(vals) && return _empty_plot("No drawdown data"; kwargs...)
    x = collect(1:length(vals))
    plot_kwargs = _merge_kwargs((;
        _THEME_KW...,
        fontfamily="Computer Modern",
        title="Drawdown",
        fill=(0, _FILL_DRAWDOWN),
        linecolor=_COLOR_DRAWDOWN,
        linetype=:steppost,
        yformatter=_fmt0,
        w=1,
        legend=false,
    ), kwargs)
    Plots.plot(x, vals; plot_kwargs...)
end

function Fastback.violin_nominal_returns_by_day(trades::AbstractVector{<:Trade}; kwargs...)
    isempty(trades) && return _empty_plot("No positions"; kwargs...)
    if !_ensure_statsplots()
        return _empty_plot("Install StatsPlots for violin plots"; kwargs...)
    end

    groups = trades |>
        @groupby(Dates.dayofweek(_.date)) |>
        @orderby(key(_)) |>
        @map(key(_) => collect(_)) |>
        collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    y = [map(t -> realized_return(t; zero_value=0.0), group) for (_, group) in groups]
    x_lbls = [Dates.dayname(day) for (day, _) in groups]

    plot_kwargs = _merge_kwargs((;
        _THEME_KW...,
        xticks=(1:length(y), x_lbls),
        fill="green",
        linewidth=0,
        title="Nominal returns by day (trade date)",
        legend=false,
    ), kwargs)
    StatsPlots.violin(y; plot_kwargs...)
end

function Fastback.violin_nominal_returns_by_day(events::AbstractVector{<:PlotEvent}; kwargs...)
    isempty(events) && return _empty_plot("No positions"; kwargs...)
    if !_ensure_statsplots()
        return _empty_plot("Install StatsPlots for violin plots"; kwargs...)
    end

    groups = events |>
        @groupby(Dates.dayofweek(_.open_dt)) |>
        @orderby(key(_)) |>
        @map(key(_) => collect(_)) |>
        collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    y = [map(e -> e.ret, group) for (_, group) in groups]
    x_lbls = [Dates.dayname(day) for (day, _) in groups]

    plot_kwargs = _merge_kwargs((;
        _THEME_KW...,
        xticks=(1:length(y), x_lbls),
        fill="green",
        linewidth=0,
        title="Nominal returns by day (event date)",
        legend=false,
    ), kwargs)
    StatsPlots.violin(y; plot_kwargs...)
end

function Fastback.violin_nominal_returns_by_hour(trades::AbstractVector{<:Trade}; kwargs...)
    isempty(trades) && return _empty_plot("No positions"; kwargs...)
    if !_ensure_statsplots()
        return _empty_plot("Install StatsPlots for violin plots"; kwargs...)
    end

    groups = trades |>
        @groupby(Dates.hour(_.date)) |>
        @orderby(key(_)) |>
        @map(key(_) => collect(_)) |>
        collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    y = [map(t -> realized_return(t; zero_value=0.0), group) for (_, group) in groups]
    x_lbls = [string(hour) for (hour, _) in groups]

    plot_kwargs = _merge_kwargs((;
        _THEME_KW...,
        xticks=(1:length(y), x_lbls),
        fontfamily="Computer Modern",
        fill="green",
        linewidth=0,
        title="Nominal returns by hour (trade time)",
        legend=false,
    ), kwargs)
    StatsPlots.violin(y; plot_kwargs...)
end

function Fastback.violin_nominal_returns_by_hour(events::AbstractVector{<:PlotEvent}; kwargs...)
    isempty(events) && return _empty_plot("No positions"; kwargs...)
    if !_ensure_statsplots()
        return _empty_plot("Install StatsPlots for violin plots"; kwargs...)
    end

    groups = events |>
        @groupby(Dates.hour(_.open_dt)) |>
        @orderby(key(_)) |>
        @map(key(_) => collect(_)) |>
        collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    y = [map(e -> e.ret, group) for (_, group) in groups]
    x_lbls = [string(hour) for (hour, _) in groups]

    plot_kwargs = _merge_kwargs((;
        _THEME_KW...,
        xticks=(1:length(y), x_lbls),
        fontfamily="Computer Modern",
        fill="green",
        linewidth=0,
        title="Nominal returns by hour (event time)",
        legend=false,
    ), kwargs)
    StatsPlots.violin(y; plot_kwargs...)
end

function Fastback.plot_nominal_cum_returns_by_hour(
    trades::AbstractVector{<:Trade},
    ret_func::Function=t -> realized_return(t; zero_value=0.0);
    kwargs...
)
    isempty(trades) && return _empty_plot("No positions"; kwargs...)

    groups = trades |>
        @groupby(Dates.hour(_.date)) |>
        @orderby(key(_)) |>
        @map(key(_) => collect(_)) |>
        collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    plt = nothing
    for (i, (hour, group)) in enumerate(groups)
        sort!(group, by=t -> t.date)
        dts = map(t -> t.date, group)
        rets = map(ret_func, group)
        cum_rets = cumsum(rets)
        lbl = "$(hour):00+"
        if i == 1
            plot_kwargs = _merge_kwargs((;
                _THEME_KW...,
                fontfamily="Computer Modern",
                legend=:topleft,
                label=lbl,
                title="Nominal returns by hour",
            ), kwargs)
            plt = Plots.plot(dts, cum_rets; plot_kwargs...)
        else
            series_kwargs = _merge_kwargs((; label=lbl), kwargs)
            Plots.plot!(plt, dts, cum_rets; series_kwargs...)
        end
        if !isempty(dts)
            Plots.annotate!(plt, dts[end], cum_rets[end],
                Plots.text(lbl, :left, 9; family="Computer Modern"))
        end
    end
    plt
end

function Fastback.plot_nominal_cum_returns_by_hour(
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

    plt = nothing
    for (i, (hour, group)) in enumerate(groups)
        sort!(group, by=e -> e.open_dt)
        dts = map(e -> e.open_dt, group)
        rets = map(ret_func, group)
        cum_rets = cumsum(rets)
        lbl = "$(hour):00+"
        if i == 1
            plot_kwargs = _merge_kwargs((;
                _THEME_KW...,
                fontfamily="Computer Modern",
                legend=:topleft,
                label=lbl,
                title="Nominal returns by hour",
            ), kwargs)
            plt = Plots.plot(dts, cum_rets; plot_kwargs...)
        else
            series_kwargs = _merge_kwargs((; label=lbl), kwargs)
            Plots.plot!(plt, dts, cum_rets; series_kwargs...)
        end
        if !isempty(dts)
            Plots.annotate!(plt, dts[end], cum_rets[end],
                Plots.text(lbl, :left, 9; family="Computer Modern"))
        end
    end
    plt
end

function Fastback.plot_nominal_cum_returns_by_hour_seq_net(trades::AbstractVector{<:Trade}; kwargs...)
    Fastback.plot_nominal_cum_returns_by_hour_seq(
        trades,
        t -> realized_return(t; zero_value=0.0),
        "Net cumulative returns by hour";
        kwargs...)
end

function Fastback.plot_nominal_cum_returns_by_hour_seq_net(events::AbstractVector{<:PlotEvent}; kwargs...)
    Fastback.plot_nominal_cum_returns_by_hour_seq(
        events,
        e -> e.ret,
        "Net cumulative returns by hour";
        kwargs...)
end

function Fastback.plot_nominal_cum_returns_by_hour_seq_gross(trades::AbstractVector{<:Trade}; kwargs...)
    Fastback.plot_nominal_cum_returns_by_hour_seq(
        trades,
        t -> realized_return(t; zero_value=0.0),
        "Gross cumulative returns by hour";
        kwargs...)
end

function Fastback.plot_nominal_cum_returns_by_hour_seq_gross(events::AbstractVector{<:PlotEvent}; kwargs...)
    Fastback.plot_nominal_cum_returns_by_hour_seq(
        events,
        e -> e.ret,
        "Gross cumulative returns by hour";
        kwargs...)
end

function Fastback.plot_nominal_cum_returns_by_hour_seq(
    trades::AbstractVector{<:Trade},
    ret_func::Function,
    title_str::String;
    kwargs...
)
    isempty(trades) && return _empty_plot("No positions"; kwargs...)

    groups = trades |>
        @groupby(Dates.hour(_.date)) |>
        @orderby(key(_)) |>
        @map(key(_) => collect(_)) |>
        collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    max_n = maximum(map(x -> length(x[2]), groups))
    min_date_str = Dates.format(minimum(map(t -> t.date, trades)), "yyyy/mm/dd")
    max_date_str = Dates.format(maximum(map(t -> t.date, trades)), "yyyy/mm/dd")

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
                _THEME_KW...,
                fontfamily="Computer Modern",
                xticks=((1, max_n), (min_date_str, max_date_str)),
                legendfontsize=9,
                yformatter=_fmt1,
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
                Plots.text(lbl, :left, 8; family="Computer Modern"))
        end
    end
    plt
end

function Fastback.plot_nominal_cum_returns_by_hour_seq(
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
                _THEME_KW...,
                fontfamily="Computer Modern",
                xticks=((1, max_n), (min_date_str, max_date_str)),
                legendfontsize=9,
                yformatter=_fmt1,
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
                Plots.text(lbl, :left, 8; family="Computer Modern"))
        end
    end
    plt
end

function Fastback.plot_nominal_cum_returns_by_weekday(
    trades::AbstractVector{<:Trade},
    ret_func::Function;
    kwargs...
)
    isempty(trades) && return _empty_plot("No positions"; kwargs...)

    groups = trades |>
        @groupby(Dates.dayofweek(_.date)) |>
        @orderby(key(_)) |>
        @map(key(_) => collect(_)) |>
        collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

    max_date = maximum(map(t -> t.date, trades))
    plt = nothing
    for (i, (weekday, group)) in enumerate(groups)
        sort!(group, by=t -> t.date)
        dts = map(t -> t.date, group)
        rets = map(ret_func, group)
        cum_rets = cumsum(rets)
        lbl = Dates.dayname(weekday)[1:3]
        if i == 1
            plot_kwargs = _merge_kwargs((;
                _THEME_KW...,
                fontfamily="Computer Modern",
                legend=:topleft,
                label=lbl,
                title="Nominal returns by weekday",
            ), kwargs)
            plt = Plots.plot(dts, cum_rets; plot_kwargs...)
        else
            series_kwargs = _merge_kwargs((; label=lbl), kwargs)
            Plots.plot!(plt, dts, cum_rets; series_kwargs...)
        end
        if !isempty(dts)
            Plots.annotate!(plt, max_date, cum_rets[end],
                Plots.text(lbl, :left, 8; family="Computer Modern"))
        end
    end
    plt
end

function Fastback.plot_nominal_cum_returns_by_weekday(
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
    plt = nothing
    for (i, (weekday, group)) in enumerate(groups)
        sort!(group, by=e -> e.open_dt)
        dts = map(e -> e.open_dt, group)
        rets = map(ret_func, group)
        cum_rets = cumsum(rets)
        lbl = Dates.dayname(weekday)[1:3]
        if i == 1
            plot_kwargs = _merge_kwargs((;
                _THEME_KW...,
                fontfamily="Computer Modern",
                legend=:topleft,
                label=lbl,
                title="Nominal returns by weekday",
            ), kwargs)
            plt = Plots.plot(dts, cum_rets; plot_kwargs...)
        else
            series_kwargs = _merge_kwargs((; label=lbl), kwargs)
            Plots.plot!(plt, dts, cum_rets; series_kwargs...)
        end
        if !isempty(dts)
            Plots.annotate!(plt, max_date, cum_rets[end],
                Plots.text(lbl, :left, 8; family="Computer Modern"))
        end
    end
    plt
end

function Fastback.plot_nominal_cum_returns_by_weekday_seq(
    trades::AbstractVector{<:Trade},
    ret_func::Function;
    kwargs...
)
    isempty(trades) && return _empty_plot("No positions"; kwargs...)

    groups = trades |>
        @groupby(Dates.dayofweek(_.date)) |>
        @orderby(key(_)) |>
        @map(key(_) => collect(_)) |>
        collect
    isempty(groups) && return _empty_plot("No positions"; kwargs...)

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
                _THEME_KW...,
                fontfamily="Computer Modern",
                legend=:bottomleft,
                label=lbl,
                title="Nominal returns by weekday",
            ), kwargs)
            plt = Plots.plot(x, cum_rets; plot_kwargs...)
        else
            series_kwargs = _merge_kwargs((; label=lbl), kwargs)
            Plots.plot!(plt, x, cum_rets; series_kwargs...)
        end
        if n_pos > 0
            Plots.annotate!(plt, n_pos + 1, cum_rets[end],
                Plots.text(lbl, :left, 8; family="Computer Modern"))
        end
    end
    plt
end

function Fastback.plot_nominal_cum_returns_by_weekday_seq(
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
                _THEME_KW...,
                fontfamily="Computer Modern",
                legend=:bottomleft,
                label=lbl,
                title="Nominal returns by weekday",
            ), kwargs)
            plt = Plots.plot(x, cum_rets; plot_kwargs...)
        else
            series_kwargs = _merge_kwargs((; label=lbl), kwargs)
            Plots.plot!(plt, x, cum_rets; series_kwargs...)
        end
        if n_pos > 0
            Plots.annotate!(plt, n_pos + 1, cum_rets[end],
                Plots.text(lbl, :left, 8; family="Computer Modern"))
        end
    end
    plt
end

end
