# Shared colors for built-in SVG and the optional Plots extension.
const _PLOT_PALETTE = ("#D7A445", "#8EA4D2", "#E36A83", "#F4F0E8",
    "#66758F", "#7DD3FC", "#86EFAC", "#FCA5A5")
const _PLOT_COLORS = (
    canvas="#182235",
    text="#F4F0E8",
    muted="#B6C0CF",
    axis="#66758F",
    balance=_PLOT_PALETTE[2],
    equity=_PLOT_PALETTE[1],
    open_orders=_PLOT_PALETTE[6],
    drawdown=_PLOT_PALETTE[3],
    exposure_gross=_PLOT_PALETTE[4],
    exposure_net=_PLOT_PALETTE[2],
    exposure_long=_PLOT_PALETTE[7],
    exposure_short=_PLOT_PALETTE[3],
)

# Shared plotting calculations used by SVG and the optional Plots extension.
@inline function _plot_drawdown_value(peak::Real, trough::Real, mode::DrawdownMode.T)
    decline = Float64(trough - peak)
    mode == DrawdownMode.Percentage ? (peak == 0 ? 0.0 : decline / peak) : decline
end

function _plot_max_drawdown_indices(vals::AbstractVector{<:Real}, mode::DrawdownMode.T)
    peak, trough, current = 0, 0, 0
    worst = 0.0

    for i in eachindex(vals)
        v = vals[i]
        isfinite(v) || continue
        (current == 0 || v > vals[current]) && (current = i)
        decline = _plot_drawdown_value(vals[current], v, mode)

        if decline < worst
            worst = decline
            peak, trough = current, i
        end
    end

    peak, trough, worst
end

function _plot_count_axis(vals; ylims=nothing)
    if ylims === nothing
        max_count = maximum((v for v in vals if isfinite(v)); init=0.0)
        bounds = (0.0, max(1.0, ceil(max_count)))
    else
        lo, hi = Float64.(ylims)
        isfinite(lo) && isfinite(hi) && lo < hi ||
            throw(ArgumentError("Axis limits must be finite and increasing."))
        bounds = (lo, hi)
    end

    lo, hi = bounds
    step = max(1.0, ceil((hi - lo) / 4))
    bounds, ceil(lo):step:floor(hi)
end

# Public plotting interface. SVG is built in; Plots adds methods when loaded.
abstract type PlotBackend end
struct SVGBackend <: PlotBackend end
struct PlotsBackend <: PlotBackend end

const _PLOT_BACKEND = Ref{Symbol}(:svg)
const _SVG_OUTPUT_FORMAT = Ref{Symbol}(:html)

"""Return the selected plotting backend (`:svg` or `:plots`)."""
plot_backend() = _PLOT_BACKEND[]

function _resolve_plot_backend(backend::Symbol)
    backend in (:svg, :plots) ||
        throw(ArgumentError("Plot backend must be :svg or :plots."))

    if backend === :plots && Base.get_extension(@__MODULE__, :FastbackPlotsExt) === nothing
        throw(ArgumentError("The :plots backend requires Plots.jl. Install Plots and run `using Plots` first."))
    end

    backend === :svg ? SVGBackend() : PlotsBackend()
end

"""
    set_plot_backend!(backend::Symbol)

Select `:svg` (built in, default) or `:plots` (requires `using Plots`).
Loading Plots does not change this setting. Individual plotting calls accept a
`backend` override. Returns the selected backend.
Configure this shared setting before starting concurrent plotting tasks.
"""
function set_plot_backend!(backend::Symbol)
    _resolve_plot_backend(backend)
    _PLOT_BACKEND[] = backend
end

"""Return the SVG output format (`:string` or `:html`)."""
svg_output_format() = _SVG_OUTPUT_FORMAT[]

function _validate_svg_output_format(format::Symbol)
    format in (:string, :html) ||
        throw(ArgumentError("SVG output format must be :string or :html."))
    format
end

"""
    set_svg_output_format!(format::Symbol)

Select inline `Base.HTML` results (`:html`, default) or SVG strings (`:string`).
SVG plotting calls accept an `output_format` override. IO-first `!` methods
always write SVG bytes and return the IO. This setting does not affect Plots.
Returns the selected format. Configure it before concurrent plotting tasks.
"""
function set_svg_output_format!(format::Symbol)
    _SVG_OUTPUT_FORMAT[] = _validate_svg_output_format(format)
end

function _unsupported_plot(backend::PlotBackend, name::Symbol)
    backend_name = backend isa SVGBackend ? :svg : :plots
    throw(ArgumentError("$(name) is not supported by the :$(backend_name) backend for these arguments."))
end

# Select the backend once at the public boundary; renderers implement these
# same functions directly with SVGBackend or PlotsBackend as their first argument.

"""Plot a title panel using the selected backend. See `set_plot_backend!`."""
function plot_title(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_title(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_title(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_title)

"""Write or add a title panel using the selected backend. See `set_plot_backend!`."""
function plot_title!(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_title!(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_title!(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_title!)

"""Plot cash balance using the selected backend. See `set_plot_backend!`."""
function plot_balance(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_balance(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_balance(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_balance)

"""Write or add cash balance using the selected backend. See `set_plot_backend!`."""
function plot_balance!(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_balance!(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_balance!(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_balance!)

"""Plot equity using the selected backend. See `set_plot_backend!`."""
function plot_equity(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_equity(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_equity(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_equity)

"""Write or add equity using the selected backend. See `set_plot_backend!`."""
function plot_equity!(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_equity!(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_equity!(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_equity!)

"""Plot open-order counts using the selected backend. See `set_plot_backend!`."""
function plot_open_orders_count(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_open_orders_count(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_open_orders_count(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_open_orders_count)

"""Write or add open-order counts using the selected backend. See `set_plot_backend!`."""
function plot_open_orders_count!(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_open_orders_count!(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_open_orders_count!(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_open_orders_count!)

"""Plot drawdowns using the selected backend. See `set_plot_backend!`."""
function plot_drawdown(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_drawdown(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_drawdown(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_drawdown)

"""Write or add drawdowns using the selected backend. See `set_plot_backend!`."""
function plot_drawdown!(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_drawdown!(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_drawdown!(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_drawdown!)

"""Plot equity and drawdowns using the selected backend. See `set_plot_backend!`."""
function plot_equity_drawdown(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_equity_drawdown(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_equity_drawdown(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_equity_drawdown)

"""Write or add equity and drawdowns using the selected backend. See `set_plot_backend!`."""
function plot_equity_drawdown!(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_equity_drawdown!(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_equity_drawdown!(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_equity_drawdown!)

"""Plot exposure using the selected backend. See `set_plot_backend!`."""
function plot_exposure(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_exposure(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_exposure(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_exposure)

"""Write or add exposure using the selected backend. See `set_plot_backend!`."""
function plot_exposure!(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_exposure!(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_exposure!(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_exposure!)

"""Plot portfolio weights using the selected backend. See `set_plot_backend!`."""
function plot_portfolio_weights_over_time(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_portfolio_weights_over_time(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_portfolio_weights_over_time(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_portfolio_weights_over_time)

"""Write or add portfolio weights using the selected backend. See `set_plot_backend!`."""
function plot_portfolio_weights_over_time!(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_portfolio_weights_over_time!(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_portfolio_weights_over_time!(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_portfolio_weights_over_time!)

"""Plot cashflows using the selected backend. See `set_plot_backend!`."""
function plot_cashflows(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_cashflows(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_cashflows(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_cashflows)

"""Write or add cashflows using the selected backend. See `set_plot_backend!`."""
function plot_cashflows!(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_cashflows!(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_cashflows!(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_cashflows!)

"""Plot cumulative realized returns by hour using the selected backend. See `set_plot_backend!`."""
function plot_realized_cum_returns_by_hour(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_realized_cum_returns_by_hour(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_realized_cum_returns_by_hour(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_realized_cum_returns_by_hour)

"""Write or add cumulative realized returns by hour using the selected backend. See `set_plot_backend!`."""
function plot_realized_cum_returns_by_hour!(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_realized_cum_returns_by_hour!(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_realized_cum_returns_by_hour!(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_realized_cum_returns_by_hour!)

"""Plot cumulative realized returns by weekday using the selected backend. See `set_plot_backend!`."""
function plot_realized_cum_returns_by_weekday(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_realized_cum_returns_by_weekday(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_realized_cum_returns_by_weekday(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_realized_cum_returns_by_weekday)

"""Write or add cumulative realized returns by weekday using the selected backend. See `set_plot_backend!`."""
function plot_realized_cum_returns_by_weekday!(args...; backend::Symbol=plot_backend(), kwargs...)
    plot_realized_cum_returns_by_weekday!(_resolve_plot_backend(backend), args...; kwargs...)
end

plot_realized_cum_returns_by_weekday!(backend::PlotBackend, args...; kwargs...) = _unsupported_plot(backend, :plot_realized_cum_returns_by_weekday!)
