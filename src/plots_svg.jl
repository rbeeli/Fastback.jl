# Built-in SVG implementation of the shared plotting interface.
using Dates
using Printf

_svg_escape(x) = replace(string(x), '&' => "&amp;", '<' => "&lt;", '>' => "&gt;",
    '"' => "&quot;", '\'' => "&apos;")
_svg_number(x) = @sprintf("%.4g", x)

function _svg_decimal(x::Real)
    x == 0 && return "0"
    # Keep cents for large amounts and enough precision for small values.
    digits = max(2, 3 - floor(Int, log10(abs(x))))
    rstrip(rstrip(@sprintf("%.*f", digits, x), '0'), '.')
end

_svg_x(x::Real) = Float64(x)
_svg_x(x::Dates.AbstractTime) = Dates.datetime2unix(DateTime(x))

function _svg_series(
    x,
    y
    ;
    label="",
    color=_PLOT_PALETTE[1],
    right=false,
    style=:step,
    baseline=nothing,
)
    length(x) == length(y) || throw(ArgumentError("Dates and values must have equal lengths."))
    baseline === nothing || length(baseline) == length(y) ||
        throw(ArgumentError("Baseline and values must have equal lengths."))
    (; x=_svg_x.(x), y=Float64.(y), label=string(label), color=string(color),
        temporal=eltype(x) <: Dates.AbstractTime, right, style, baseline)
end

function _svg_collector(pv; xaxis_mode=:date, kwargs...)
    xaxis_mode in (:date, :index) || throw(ArgumentError("xaxis_mode must be :date or :index."))
    _svg_series(xaxis_mode === :date ? dates(pv) : collect(eachindex(values(pv))),
        values(pv); kwargs...)
end

function _svg_limits(vals, limits)
    if limits !== nothing
        lo, hi = Float64.(limits)
        isfinite(lo) && isfinite(hi) && lo < hi ||
            throw(ArgumentError("Axis limits must be finite and increasing."))
        return lo, hi
    end

    finite = filter(isfinite, vals)
    isempty(finite) && return (0.0, 1.0)
    lo, hi = extrema(finite)
    pad = lo == hi ? max(abs(lo) * 0.05, 0.5) : (hi - lo) * 0.055
    lo - pad, hi + pad
end

function _svg_text(
    io,
    x,
    y,
    text
    ;
    anchor="start",
    color=_PLOT_COLORS.muted,
    size=12,
)
    println(io, "<text x=\"$x\" y=\"$y\" text-anchor=\"$anchor\" fill=\"$color\" font-size=\"$size\">$(_svg_escape(text))</text>")
end

function _svg_chart(
    io::IO,
    series
    ;
    title="",
    width::Real=800,
    height::Real=450,
    xlabel="",
    ylabel="",
    ylabel_right="",
    legend::Bool=true,
    legend_center::Bool=false,
    end_labels::Bool=false,
    ylims=nothing,
    yticks=nothing,
    right_ylims=nothing,
    percentage::Bool=false,
    right_percentage::Bool=false,
    axes::Bool=true,
)
    isfinite(width) && isfinite(height) && width >= 320 && height >= 200 ||
        throw(ArgumentError("SVG dimensions must be finite, width ≥ 320 and height ≥ 200."))
    temporal = unique(s.temporal for s in series if !isempty(s.x))
    length(temporal) <= 1 || throw(ArgumentError("Cannot mix date and numeric x axes."))
    xs = Float64[x for s in series for x in s.x if isfinite(x)]
    xmin, xmax = _svg_limits(xs, nothing)
    has_right = any(s.right for s in series)
    legend_positions = Tuple{Float64,Float64}[]
    lx, ly = 85.0, 52.0

    for s in series
        (!legend || isempty(s.label)) && continue
        lx + 8length(s.label) > width - 25 && lx > 85 && (lx = 85.0; ly += 16)
        push!(legend_positions, (lx, ly))
        lx += 8length(s.label) + 24
    end

    left, top = 85.0, max(85.0, ly + 30)
    height > top + 80 || throw(ArgumentError("Increase height to fit the legend and axes."))
    right_margin = has_right ? 90 : 30
    end_labels && (right_margin = max(right_margin, 16 + maximum((8length(s.label) for s in series); init=0)))
    pw, ph = width - left - right_margin, height - top - 60
    pw > 0 || throw(ArgumentError("Increase width to fit the end labels and axes."))
    ranges = map((false, true)) do right
        ys = Float64[]

        for s in series
            s.right == right || continue
            append!(ys, s.y)
            s.baseline === nothing || append!(ys, s.baseline)
            s.style === :sticks && push!(ys, 0.0)
        end

        _svg_limits(ys, right ? right_ylims : ylims)
    end

    px(x) = left + (x - xmin) / (xmax - xmin) * pw
    py(y, right) = begin
        lo, hi = ranges[right ? 2 : 1]
        top + ph - (y - lo) / (hi - lo) * ph
    end

    println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\" role=\"img\">")
    println(io, "<title>$(_svg_escape(title))</title><rect width=\"100%\" height=\"100%\" fill=\"$(_PLOT_COLORS.canvas)\"/><g font-family=\"sans-serif\">")
    _svg_text(io, 24, 30, title; color=_PLOT_COLORS.text, size=18)

    if !axes
        println(io, "</g></svg>")
        return io
    end

    if legend && legend_center
        index = 1
        row_y = nothing

        for s in series
            isempty(s.label) && continue
            _, ly = legend_positions[index]

            if ly != row_y
                row_y === nothing || println(io, "</text>")
                print(io, "<text x=\"$(width / 2)\" y=\"$ly\" text-anchor=\"middle\" font-size=\"12\">")
            end

            gap = ly == row_y ? 24 : 0
            print(io, "<tspan dx=\"$gap\" fill=\"$(_svg_escape(s.color))\">$(_svg_escape(s.label))</tspan>")
            row_y = ly
            index += 1
        end

        row_y === nothing || println(io, "</text>")
    elseif legend
        index = 1

        for s in series
            isempty(s.label) && continue
            lx, ly = legend_positions[index]
            _svg_text(io, lx, ly, s.label; color=_svg_escape(s.color))
            index += 1
        end
    end

    for right in (false, true)
        right && !has_right && continue
        ax = right ? left + pw : left
        println(io, "<path d=\"M $ax $top V $(top + ph)\" stroke=\"$(_PLOT_COLORS.axis)\" fill=\"none\"/>")
        lo, hi = ranges[right ? 2 : 1]

        ticks = !right && yticks !== nothing ? yticks : range(lo, hi; length=5)

        for y in ticks
            pct = right ? right_percentage : percentage
            label = pct ? string(_svg_decimal(100y), "%") : _svg_decimal(y)
            _svg_text(io, ax + (right ? 8 : -8), py(y, right) + 4, label;
                anchor=right ? "start" : "end")
        end

        _svg_text(io, ax, top - 10, right ? ylabel_right : ylabel;
            anchor=right ? "end" : "start")
    end

    println(io, "<path d=\"M $left $(top + ph) H $(left + pw)\" stroke=\"$(_PLOT_COLORS.axis)\"/>")

    if !isempty(xs)

        for x in range(minimum(xs), maximum(xs); length=minimum(xs) == maximum(xs) ? 1 : 5)
            label = temporal == [true] ? Dates.format(Dates.unix2datetime(x), "yyyy-mm-dd HH:MM") : _svg_number(x)
            _svg_text(io, px(x), top + ph + 22, label; anchor="middle", size=10)
        end
    end

    _svg_text(io, left + pw / 2, height - 10, xlabel; anchor="middle")
    # Nested viewport clips paths without document-global IDs (safe for inline SVGs).
    println(io, "<svg x=\"$left\" y=\"$top\" width=\"$pw\" height=\"$ph\" viewBox=\"$left $top $pw $ph\" overflow=\"hidden\">")

    for s in series
        color = _svg_escape(s.color)
        i = 1

        while i <= length(s.y)
            valid(j) = isfinite(s.x[j]) && isfinite(s.y[j]) &&
                (s.baseline === nothing || isfinite(s.baseline[j]))

            if !valid(i)
                i += 1
                continue
            end

            last = i

            while last < length(s.y) && valid(last + 1)
                last += 1
            end

            if s.style in (:sticks, :markers)

                for j in i:last
                    x, y = px(s.x[j]), py(s.y[j], s.right)
                    s.style === :sticks && println(io, "<path d=\"M $x $(py(0, s.right)) V $y\" stroke=\"$color\"/>")
                    println(io, "<circle cx=\"$x\" cy=\"$y\" r=\"3\" fill=\"$color\"/>")
                end
            else
                path = IOBuffer()
                print(path, "M $(px(s.x[i])) $(py(s.y[i], s.right))")

                for j in (i + 1):last
                    print(path, s.style === :step ? " H $(px(s.x[j])) V $(py(s.y[j], s.right))" :
                        " L $(px(s.x[j])) $(py(s.y[j], s.right))")
                end

                line = String(take!(path))

                if s.baseline !== nothing
                    print(path, line, " L $(px(s.x[last])) $(py(s.baseline[last], s.right))")

                    for j in (last - 1):-1:i
                        print(path, s.style === :step ? " V $(py(s.baseline[j], s.right)) H $(px(s.x[j]))" :
                            " L $(px(s.x[j])) $(py(s.baseline[j], s.right))")
                    end

                    println(io, "<path d=\"$(String(take!(path))) Z\" fill=\"$color\" fill-opacity=\"0.3\"/>")
                end

                println(io, "<path d=\"$line\" fill=\"none\" stroke=\"$color\" stroke-opacity=\"0.9\" stroke-width=\"1.5\"/>")
                i == last && println(io, "<circle cx=\"$(px(s.x[i]))\" cy=\"$(py(s.y[i], s.right))\" r=\"2\" fill=\"$color\"/>")
            end

            i = last + 1
        end
    end

    println(io, "</svg>")

    if end_labels
        println(io, "<g class=\"series-end-labels\">")

        for s in series
            isempty(s.label) && continue
            last = findlast(i -> isfinite(s.x[i]) && isfinite(s.y[i]), eachindex(s.y))
            last === nothing && continue
            _svg_text(io, px(s.x[last]) + 6, py(s.y[last], s.right) + 4, s.label;
                color=_svg_escape(s.color))
        end

        println(io, "</g>")
    end

    println(io, "</g></svg>")
    io
end

function plot_title!(
    backend::SVGBackend,
    io::IO,
    title
    ;
    kwargs...,
)
    _svg_chart(io, []; title, axes=false, kwargs...)
end

function plot_balance!(
    backend::SVGBackend,
    io::IO,
    pv::PeriodicValues
    ;
    title="Balance",
    xaxis_mode=:date,
    label="Cash balance",
    color=_PLOT_COLORS.balance,
    legend::Bool=false,
    kwargs...,
)
    _svg_chart(io, [_svg_collector(pv; xaxis_mode, label, color)]; title, legend, kwargs...)
end

function plot_equity!(
    backend::SVGBackend,
    io::IO,
    pv::PeriodicValues
    ;
    title="Equity",
    xaxis_mode=:date,
    label="Equity",
    color=_PLOT_COLORS.equity,
    legend::Bool=false,
    kwargs...,
)
    _svg_chart(io, [_svg_collector(pv; xaxis_mode, label, color)]; title, legend, kwargs...)
end

function plot_open_orders_count!(
    backend::SVGBackend,
    io::IO,
    pv::PeriodicValues
    ;
    title="Open orders count",
    xaxis_mode=:date,
    label="Open orders count",
    color=_PLOT_COLORS.open_orders,
    legend::Bool=false,
    ylims=nothing,
    kwargs...,
)
    bounds, ticks = _plot_count_axis(values(pv); ylims)
    series = _svg_collector(pv; xaxis_mode, label, color)
    _svg_chart(io, [series]; title, legend, ylims=bounds, yticks=ticks, kwargs...)
end

function plot_drawdown!(
    backend::SVGBackend,
    io::IO,
    pv::DrawdownValues
    ;
    title="Equity drawdowns",
    legend::Bool=false,
    xaxis_mode=:date,
    ylims=pv.mode == DrawdownMode.Percentage ? (-1.0, 0.0) : nothing,
    kwargs...,
)
    s = _svg_collector(pv; xaxis_mode, label="Drawdown", color=_PLOT_COLORS.drawdown,
        baseline=zeros(length(values(pv))))
    _svg_chart(io, [s]; title, legend, ylims, percentage=pv.mode == DrawdownMode.Percentage, kwargs...)
end

function plot_equity_drawdown!(
    backend::SVGBackend,
    io::IO,
    equity::PeriodicValues,
    dd::DrawdownValues
    ;
    title="Equity & drawdown",
    legend::Bool=false,
    xaxis_mode=:date,
    show_max_dd::Bool=true,
    kwargs...,
)
    series = [_svg_collector(equity; xaxis_mode, label="Equity"),
        _svg_collector(dd; xaxis_mode, label="Drawdown", color=_PLOT_COLORS.drawdown, right=true,
            baseline=zeros(length(values(dd))))]
    pct = dd.mode == DrawdownMode.Percentage

    if show_max_dd
        peak, trough, _ = _plot_max_drawdown_indices(values(equity), dd.mode)

        if peak != 0
            s = series[1]
            push!(series, _svg_series(s.x[[peak, trough]], s.y[[peak, trough]];
                style=:markers, color=_PLOT_COLORS.drawdown, label="Max drawdown") |> x -> merge(x, (; temporal=s.temporal)))
        end
    end

    _svg_chart(io, series; title, legend, ylabel="Equity", ylabel_right="Drawdown",
        right_percentage=pct, right_ylims=pct ? (-1.0, 0.0) : nothing, kwargs...)
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
    legend_center::Bool=true,
    xaxis_mode=:date,
    kwargs...,
)
    series = [_svg_collector(pv; xaxis_mode, label, color) for (pv, label, color) in
        ((gross, "Gross", _PLOT_COLORS.exposure_gross), (net, "Net", _PLOT_COLORS.exposure_net),
        (long, "Long", _PLOT_COLORS.exposure_long), (short, "Short", _PLOT_COLORS.exposure_short)) if pv !== nothing]
    _svg_chart(io, series; title, legend_center, kwargs...)
end

function plot_portfolio_weights_over_time!(
    backend::SVGBackend,
    io::IO,
    dts::AbstractVector{<:Dates.AbstractTime},
    weights::AbstractMatrix{<:Real},
    symbols::AbstractVector
    ;
    title="Portfolio weights over time",
    kwargs...,
)
    size(weights) == (length(dts), length(symbols)) ||
        throw(ArgumentError("Weights must have one row per date and one column per symbol."))
    all(isfinite, weights) || throw(ArgumentError("Portfolio weights must be finite."))
    positive, negative = zeros(length(dts)), zeros(length(dts))
    series = []

    for (j, symbol) in enumerate(symbols)
        w = weights[:, j]
        base = [w[i] >= 0 ? positive[i] : negative[i] for i in eachindex(w)]
        top = base + w

        for i in eachindex(w)
            w[i] >= 0 ? (positive[i] = top[i]) : (negative[i] = top[i])
        end

        push!(series, _svg_series(dts, top; baseline=base, label=string(symbol),
            color=_PLOT_PALETTE[mod1(j, length(_PLOT_PALETTE))]))
    end

    _svg_chart(io, series; title, percentage=true, kwargs...)
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
    width=800,
    height=450,
    kwargs...,
)
    kinds = sort!(unique(cf.kind for cf in acc.cashflows); by=Int)
    isempty(kinds) && return _svg_chart(io, []; title="No cashflow data", width, height, kwargs...)
    # Each panel retains the recorded native amounts, matching the Plots backend.
    panels = [begin
        cfs = filter(cf -> cf.kind == kind, acc.cashflows)
        s = _svg_series([cf.dt for cf in cfs], [cf.amount for cf in cfs]; style=:sticks)
        sprint(out -> _svg_chart(out, [s]; title=string(kind), width, height, kwargs...))
    end for kind in kinds]
    println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$(height * length(kinds))\" viewBox=\"0 0 $width $(height * length(kinds))\">")

    for (i, panel) in enumerate(panels)
        println(io, "<g transform=\"translate(0 $((i - 1) * height))\">$panel</g>")
    end

    println(io, "</svg>")
    io
end

function _svg_returns!(
    io,
    trades,
    groupby
    ;
    return_basis=:gross,
    xaxis_mode=:date,
    title="Realized cumulative returns",
    legend::Bool=false,
    end_labels::Bool=true,
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

    series = []

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

        ys = cumprod(1 .+ nums ./ dens) .- 1
        label = groupby === Dates.hour ? "$(key):00" : Dates.dayname(key)
        push!(series, _svg_series(xaxis_mode === :date ? dts : collect(eachindex(ys)), ys;
            label, style=:line, color=_PLOT_PALETTE[mod1(length(series) + 1, length(_PLOT_PALETTE))]))
    end

    _svg_chart(io, series; title, legend, end_labels, percentage=true, kwargs...)
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

function plot_title(backend::SVGBackend, args...; kwargs...)
    _render_svg(plot_title!, backend, args...; kwargs...)
end

function plot_balance(backend::SVGBackend, args...; kwargs...)
    _render_svg(plot_balance!, backend, args...; kwargs...)
end

function plot_equity(backend::SVGBackend, args...; kwargs...)
    _render_svg(plot_equity!, backend, args...; kwargs...)
end

function plot_open_orders_count(backend::SVGBackend, args...; kwargs...)
    _render_svg(plot_open_orders_count!, backend, args...; kwargs...)
end

function plot_drawdown(backend::SVGBackend, args...; kwargs...)
    _render_svg(plot_drawdown!, backend, args...; kwargs...)
end

function plot_equity_drawdown(backend::SVGBackend, args...; kwargs...)
    _render_svg(plot_equity_drawdown!, backend, args...; kwargs...)
end

function plot_exposure(backend::SVGBackend, args...; kwargs...)
    _render_svg(plot_exposure!, backend, args...; kwargs...)
end

function plot_portfolio_weights_over_time(backend::SVGBackend, args...; kwargs...)
    _render_svg(plot_portfolio_weights_over_time!, backend, args...; kwargs...)
end

function plot_cashflows(backend::SVGBackend, args...; kwargs...)
    _render_svg(plot_cashflows!, backend, args...; kwargs...)
end

function plot_realized_cum_returns_by_hour(backend::SVGBackend, args...; kwargs...)
    _render_svg(plot_realized_cum_returns_by_hour!, backend, args...; kwargs...)
end

function plot_realized_cum_returns_by_weekday(backend::SVGBackend, args...; kwargs...)
    _render_svg(plot_realized_cum_returns_by_weekday!, backend, args...; kwargs...)
end
