"""
Standalone SVG charts: line, scatter, categorical bar, and stacked interval bar charts with numeric
or temporal x values and up to two independent vertical axes.

Axis sides, scales, and tick formats are symbols: `:left`/`:right`, `:linear`/`:logarithmic`, and
`:number`/`:percentage`. A chart legend is a positive column count, or `nothing` to hide it.
Temporal x values are `DateTime` (interpreted as UTC) or `Date` (midnight UTC).
"""
module Charts

using Dates
using Printf

export AxisOptions,
    BarChartOptions,
    BarSeries,
    ChartOptions,
    DARK_PLOT_THEME,
    LineSeries,
    PlotTheme,
    PointLabel,
    ReferenceLine,
    ScatterSeries,
    StackedBarSeries,
    render_svg_bar_chart,
    render_svg_line_chart,
    render_svg_scatter_chart,
    render_svg_stacked_bar_chart,
    write_svg_bar_chart,
    write_svg_line_chart,
    write_svg_scatter_chart,
    write_svg_stacked_bar_chart

const LEFT = 100.0
const LEGEND_ROW_HEIGHT = 31
const AXIS_SIDES = (:left, :right)
const AXIS_SCALES = (:linear, :logarithmic)
const TICK_FORMATS = (:number, :percentage)

"""
Shared chart colors and typography. Colors accept CSS color names, hexadecimal colors, or CSS
color functions; opacities lie in `[0, 1]`; `series_palette` repeats for series without explicit
colors.
"""
struct PlotTheme
    canvas::String
    text::String
    muted_text::String
    axis::String
    reference::String
    reference_opacity::Float64
    legend_background::String
    legend_opacity::Float64
    series_palette::Vector{String}
    series_opacity::Float64
    grid::Bool
    font_family::String
end

"""Default dark presentation theme."""
const DARK_PLOT_THEME = PlotTheme(
    "#182235",
    "#F4F0E8",
    "#B6C0CF",
    "#66758F",
    "#F0C36A",
    0.95,
    "#182235",
    0.88,
    ["#D7A445", "#8EA4D2", "#E36A83", "#F4F0E8", "#66758F", "#7DD3FC", "#86EFAC", "#FCA5A5"],
    0.9,
    false,
    "Inter, ui-sans-serif, system-ui, sans-serif",
)

"""
Independent settings for one vertical axis. `limits` clips data outside explicit bounds; a
logarithmic axis label receives a scale suffix; `tick_count` lies in 2..1000.
"""
Base.@kwdef struct AxisOptions
    scale::Symbol = :linear
    limits::Union{Nothing,Tuple{Float64,Float64}} = nothing
    label::Union{Nothing,String} = nothing
    tick_count::Int = 6
    format::Symbol = :number
end

"""A horizontal threshold or boundary, included in automatic axis bounds."""
Base.@kwdef struct ReferenceLine
    value::Float64
    axis::Symbol = :left
    color::Union{Nothing,String} = nothing
    label::Union{Nothing,String} = nothing
end

ReferenceLine(value::Real; kwargs...) = ReferenceLine(; value=Float64(value), kwargs...)

"""
Common options of a standalone chart. `height` is a minimum: additional legend rows increase it.
`x_date_format` is a strftime format for temporal x values (`%Y`, `%m`, `%d`, `%H`, `%M`, `%S`,
`%.3f`, `%.6f`, `%.9f`, `%b`, `%y`, `%%`). A right-assigned series or reference activates the right
axis automatically; `right_y_axis` overrides its settings.
"""
Base.@kwdef struct ChartOptions
    width::Int = 1_600
    height::Int = 900
    title::Union{Nothing,String} = nothing
    subtitle::Union{Nothing,String} = nothing
    x_label::Union{Nothing,String} = nothing
    x_tick_count::Int = 6
    x_date_format::Union{Nothing,String} = nothing
    left_y_axis::AxisOptions = AxisOptions()
    right_y_axis::Union{Nothing,AxisOptions} = nothing
    legend::Union{Nothing,Int} = 6
    theme::PlotTheme = DARK_PLOT_THEME
    reference_lines::Vector{ReferenceLine} = ReferenceLine[]
end

"""
One line. Sample order is retained; non-finite values split the line, and isolated finite samples
appear as points.
"""
struct LineSeries
    label::String
    x::AbstractVector
    values::Vector{Float64}
    axis::Symbol
    color::Union{Nothing,String}
    width::Float64
end

LineSeries(label::AbstractString, x::AbstractVector, values::AbstractVector{<:Real}; axis::Symbol=:left,
    color::Union{Nothing,AbstractString}=nothing, width::Real=1.2) =
    LineSeries(String(label), x, collect(Float64, values), axis, _optional_string(color), Float64(width))

"""A visible label offset in pixels from a scatter marker's center; positive y moves down."""
struct PointLabel
    text::String
    offset::Tuple{Float64,Float64}
end

PointLabel(text::AbstractString; offset::Tuple{Real,Real}=(8.0, -8.0)) =
    PointLabel(String(text), (Float64(offset[1]), Float64(offset[2])))

"""Scatter samples sharing one marker style and vertical axis."""
struct ScatterSeries
    label::String
    x::AbstractVector
    values::Vector{Float64}
    axis::Symbol
    color::Union{Nothing,String}
    radius::Float64
    opacity::Union{Nothing,Float64}
    labels::Union{Nothing,Vector{Union{Nothing,PointLabel}}}
end

ScatterSeries(label::AbstractString, x::AbstractVector, values::AbstractVector{<:Real}; axis::Symbol=:left,
    color::Union{Nothing,AbstractString}=nothing, radius::Real=4.0, opacity::Union{Nothing,Real}=nothing,
    labels=nothing) =
    ScatterSeries(String(label), x, collect(Float64, values), axis, _optional_string(color), Float64(radius),
        isnothing(opacity) ? nothing : Float64(opacity),
        isnothing(labels) ? nothing : collect(Union{Nothing,PointLabel}, labels))

"""One series of categorical bars with optional `(lower, upper)` intervals drawn as error bars."""
struct BarSeries
    label::String
    values::Vector{Float64}
    axis::Symbol
    color::Union{Nothing,String}
    intervals::Union{Nothing,Vector{Tuple{Float64,Float64}}}
end

BarSeries(label::AbstractString, values::AbstractVector{<:Real}; axis::Symbol=:left,
    color::Union{Nothing,AbstractString}=nothing, intervals=nothing) =
    BarSeries(String(label), collect(Float64, values), axis, _optional_string(color),
        isnothing(intervals) ? nothing : [(Float64(lower), Float64(upper)) for (lower, upper) in intervals])

"""One series of stacked interval bars; positive and negative values stack separately per axis."""
struct StackedBarSeries
    label::String
    values::Vector{Float64}
    axis::Symbol
    color::Union{Nothing,String}
end

StackedBarSeries(label::AbstractString, values::AbstractVector{<:Real}; axis::Symbol=:left,
    color::Union{Nothing,AbstractString}=nothing) =
    StackedBarSeries(String(label), collect(Float64, values), axis, _optional_string(color))

"""
Options of a categorical bar chart: its shared chart options (bar axes are linear), the fraction
of each category occupied by its bar group in `(0, 1]`, and whether to rotate category labels
(`nothing` rotates automatically for long or many labels).
"""
Base.@kwdef struct BarChartOptions
    chart::ChartOptions = ChartOptions(; height=600)
    bar_width::Float64 = 0.6
    rotate_labels::Union{Nothing,Bool} = nothing
end

_optional_string(value) = isnothing(value) ? nothing : String(value)

# Number text. Coordinates, bounds, and labels use fixed, platform-independent formatting, so
# equal inputs produce byte-identical documents.

"""Shortest round-trip decimal text without an exponent; integral values have no fraction."""
function _display(value::Float64)::String
    isnan(value) && return "NaN"
    isinf(value) && return value > 0 ? "inf" : "-inf"
    value == 0.0 && return signbit(value) ? "-0" : "0"
    text = repr(value)
    negative = startswith(text, '-')
    negative && (text = text[2:end])
    mantissa, exponent = occursin('e', text) ? split(text, 'e') : (text, "0")
    integer_part, fraction_part = occursin('.', mantissa) ? split(mantissa, '.') : (mantissa, "")
    digits = integer_part * fraction_part
    point = length(integer_part) + parse(Int, exponent)
    while length(digits) > 1 && startswith(digits, '0')
        digits = digits[2:end]
        point -= 1
    end
    digits = rstrip(digits, '0')
    result = if point <= 0
        "0." * "0"^(-point) * digits
    elseif point >= length(digits)
        digits * "0"^(point - length(digits))
    else
        digits[1:point] * "." * digits[(point + 1):end]
    end
    return negative ? "-" * result : result
end

_display(value::Integer)::String = string(value)

"""Debug text of a finite moderate value: the display text with a fraction when integral."""
function _debug(value::Float64)::String
    text = _display(value)
    return occursin('.', text) || occursin('n', text) ? text : text * ".0"
end

_fixed(value::Float64, precision::Int)::String = Printf.format(Printf.Format("%.$(precision)f"), value)
_fixed2(value::Float64)::String = @sprintf("%.2f", value)

function _scientific3(value::Float64)::String
    text = @sprintf("%.3e", value)
    mantissa, exponent = split(text, 'e')
    return mantissa * "e" * string(parse(Int, exponent))
end

function number_label(value::Float64)::String
    magnitude = abs(value)
    magnitude == 0.0 && return "0"
    (magnitude >= 1.0e6 || (magnitude > 0.0 && magnitude < 1.0e-3)) && return _scientific3(value)
    precision = magnitude >= 1_000.0 ? 0 : magnitude >= 100.0 ? 1 : magnitude >= 10.0 ? 2 :
                magnitude >= 1.0 ? 3 : magnitude >= 0.1 ? 4 : magnitude >= 0.01 ? 5 : 6
    label = _fixed(value, precision)
    precision == 0 && return label
    return String(rstrip(rstrip(label, '0'), '.'))
end

function escape_xml(value::AbstractString)::String
    io = IOBuffer()
    for character in value
        if character == '&'
            print(io, "&amp;")
        elseif character == '<'
            print(io, "&lt;")
        elseif character == '>'
            print(io, "&gt;")
        elseif character == '"'
            print(io, "&quot;")
        elseif character == '\''
            print(io, "&apos;")
        elseif character in ('\t', '\n', '\r')
            print(io, character)
        elseif character < ' ' || character in ('￾', '￿')
            print(io, ' ')
        else
            print(io, character)
        end
    end
    return String(take!(io))
end

# X coordinates

struct XPoint
    temporal::Bool
    value::Float64
    time::DateTime
end

_numeric_point(value::Float64) = XPoint(false, value, DateTime(0))
_temporal_point(time::DateTime) = XPoint(true, 0.0, time)

_is_numeric_x(x::AbstractVector) = eltype(x) <: Real
_is_temporal_x(x::AbstractVector) = eltype(x) <: Union{Date,DateTime}

function _x_point(x::AbstractVector, index::Int)::Union{Nothing,XPoint}
    value = x[index]
    value isa DateTime && return _temporal_point(value)
    value isa Date && return _temporal_point(DateTime(value))
    numeric = Float64(value)
    return isfinite(numeric) ? _numeric_point(numeric) : nothing
end

function _compare(left::XPoint, right::XPoint)::Int
    left.temporal != right.temporal && return 0
    left.temporal && return cmp(left.time, right.time)
    # Total order: -0.0 precedes 0.0, matching a total float comparison.
    return isless(left.value, right.value) ? -1 : isless(right.value, left.value) ? 1 : 0
end

# Elapsed seconds as whole seconds plus the fractional nanoseconds, the reference duration conversion.
function _seconds(difference::Millisecond)::Float64
    milliseconds = Dates.value(difference)
    seconds, remainder = fldmod(milliseconds, 1_000)
    return Float64(seconds) + Float64(remainder * 1_000_000) / 1.0e9
end

function _fraction(value::Float64, lower::Float64, upper::Float64)::Float64
    lower >= upper && return 0.5
    ratio = isfinite(upper - lower) ? (value - lower) / (upper - lower) :
            (value / 2.0 - lower / 2.0) / (upper / 2.0 - lower / 2.0)
    # Off-canvas coordinates must remain finite even when explicit limits exclude extreme values.
    return clamp(ratio, -1.0e6, 1.0e6)
end

function _fraction(point::XPoint, start::XPoint, stop::XPoint)::Float64
    point.temporal == start.temporal == stop.temporal || return 0.5
    point.temporal || return _fraction(point.value, start.value, stop.value)
    return _fraction(_seconds(point.time - start.time), 0.0, _seconds(stop.time - start.time))
end

function _sample(x::AbstractVector, values::Vector{Float64}, index::Int)
    1 <= index <= length(values) || return nothing
    value = values[index]
    isfinite(value) || return nothing
    point = _x_point(x, index)
    return isnothing(point) ? nothing : (point, value)
end

# Bounds and axes

mutable struct Bounds
    lower::Float64
    upper::Float64
end

Bounds() = Bounds(Inf, -Inf)

function include!(bounds::Bounds, value::Float64)
    bounds.lower = min(bounds.lower, value)
    bounds.upper = max(bounds.upper, value)
    return bounds
end

isempty_bounds(bounds::Bounds) = bounds.lower > bounds.upper

struct Axis
    lower::Float64
    upper::Float64
    options::AxisOptions
end

function Axis(bounds::Bounds, options::AxisOptions, bars::Bool)
    isempty_bounds(bounds) && throw(ArgumentError("Axis has no finite samples or references."))
    logarithmic = options.scale == :logarithmic
    logarithmic && (bars || bounds.lower <= 0.0) &&
        throw(ArgumentError("Logarithmic axes require positive values; bar axes must be linear."))
    if !isnothing(options.limits)
        lower, upper = options.limits
        isfinite(lower) && isfinite(upper) && lower < upper && !(logarithmic && (lower <= 0.0 || log(lower) >= log(upper))) ||
            throw(ArgumentError("Axis limits must be finite and increasing, and positive on logarithmic axes."))
        return Axis(lower, upper, options)
    end
    bounds = Bounds(bounds.lower, bounds.upper)
    bars && include!(bounds, 0.0)
    lower = logarithmic ? log(bounds.lower) : bounds.lower
    upper = logarithmic ? log(bounds.upper) : bounds.upper
    flat = isequal(lower, upper)
    padding = flat ? max(abs(lower) * 0.05, 0.5) : upper * 0.055 - lower * 0.055
    if !bars || lower < 0.0 || flat
        lower = max(lower - padding, -floatmax(Float64))
    end
    if !bars || upper > 0.0 || flat
        upper = min(upper + padding, floatmax(Float64))
    end
    if logarithmic
        lower = max(exp(lower), nextfloat(0.0))
        upper = min(exp(upper), floatmax(Float64))
    end
    return Axis(lower, upper, options)
end

_axis_fraction(axis::Axis, value::Float64) = axis.options.scale == :logarithmic ?
    _fraction(log(value), log(axis.lower), log(axis.upper)) : _fraction(value, axis.lower, axis.upper)

function _ticks(axis::Axis)::Vector{Float64}
    lower, upper, count = axis.lower, axis.upper, axis.options.tick_count
    if axis.options.scale == :logarithmic
        ticks = Float64[]
        exponent = floor(log10(lower))
        while exponent <= ceil(log10(upper))
            magnitude = 10.0^exponent
            for multiplier in (1.0, 1.5, 2.0, 3.0, 5.0, 7.5)
                value = multiplier * magnitude
                lower <= value <= upper && push!(ticks, value)
            end
            exponent += 1.0
        end
        length(ticks) >= 3 && return [ticks[index + 1] for index in _tick_indices(length(ticks), count)]
        return [clamp(exp(log(lower) * (1.0 - index / (count - 1)) + log(upper) * (index / (count - 1))), lower, upper)
                for index in 0:(count - 1)]
    end
    rough_step = upper / (count - 1) - lower / (count - 1)
    magnitude = 10.0^floor(log10(rough_step))
    ratio = rough_step / magnitude
    index = findfirst(step -> step >= ratio, (1.0, 2.0, 2.5, 5.0, 10.0))
    step = (isnothing(index) ? 10.0 : (1.0, 2.0, 2.5, 5.0, 10.0)[index]) * magnitude
    (!isfinite(step) || step <= 0.0) && return [lower, upper]
    first_tick = ceil(lower / step)
    return [value for value in ((first_tick + index) * step for index in 0:(count - 1))
            if isfinite(value) && lower <= value <= upper]
end

function _tick_indices(length::Int, desired::Int)::Vector{Int}
    count = min(length, desired)
    count < 2 && return collect(0:(count - 1))
    span = length - 1
    return [index * div(span, count - 1) + div(index * rem(span, count - 1), count - 1) for index in 0:(count - 1)]
end

# Validation and legend

_side_index(side::Symbol) = side == :right ? 2 : 1

function _validate_side(side::Symbol, context::AbstractString)
    side in AXIS_SIDES || throw(ArgumentError("$(context) axis $(repr(side)) must be :left or :right."))
    return side
end

function _validate_axis_options(options::AxisOptions)
    options.scale in AXIS_SCALES || throw(ArgumentError("Axis scale $(repr(options.scale)) must be :linear or :logarithmic."))
    options.format in TICK_FORMATS || throw(ArgumentError("Tick format $(repr(options.format)) must be :number or :percentage."))
    return nothing
end

const _STRFTIME_ITEMS = ("%Y", "%m", "%d", "%H", "%M", "%S", "%.3f", "%.6f", "%.9f", "%b", "%y", "%%")

function _strftime_items(format::AbstractString)
    items = String[]
    index = firstindex(format)
    while index <= lastindex(format)
        if format[index] == '%'
            matched = findfirst(item -> startswith(SubString(format, index), item), _STRFTIME_ITEMS)
            isnothing(matched) && return nothing
            item = _STRFTIME_ITEMS[matched]
            push!(items, item)
            index += ncodeunits(item)
        else
            next = nextind(format, index)
            push!(items, String(format[index:prevind(format, next)]))
            index = next
        end
    end
    return items
end

function _strftime(time::DateTime, format::AbstractString)::String
    items = something(_strftime_items(format))
    io = IOBuffer()
    for item in items
        if item == "%Y"
            print(io, lpad(year(time), 4, '0'))
        elseif item == "%m"
            print(io, lpad(month(time), 2, '0'))
        elseif item == "%d"
            print(io, lpad(day(time), 2, '0'))
        elseif item == "%H"
            print(io, lpad(hour(time), 2, '0'))
        elseif item == "%M"
            print(io, lpad(minute(time), 2, '0'))
        elseif item == "%S"
            print(io, lpad(second(time), 2, '0'))
        elseif item == "%.3f"
            print(io, ".", lpad(millisecond(time), 3, '0'))
        elseif item == "%.6f"
            print(io, ".", lpad(millisecond(time), 3, '0'), "000")
        elseif item == "%.9f"
            print(io, ".", lpad(millisecond(time), 3, '0'), "000000")
        elseif item == "%b"
            print(io, Dates.monthabbr(time))
        elseif item == "%y"
            print(io, lpad(mod(year(time), 100), 2, '0'))
        elseif item == "%%"
            print(io, "%")
        else
            print(io, item)
        end
    end
    return String(take!(io))
end

function _validate_options(options::ChartOptions)::Vector{Bounds}
    bounds = [Bounds(), Bounds()]
    theme = options.theme
    !isempty(theme.series_palette) &&
        all(value -> isfinite(value) && 0.0 <= value <= 1.0, (theme.series_opacity, theme.legend_opacity, theme.reference_opacity)) &&
        (isnothing(options.legend) || options.legend > 0) ||
        throw(ArgumentError("Invalid palette, opacity, or legend columns."))
    right = something(options.right_y_axis, AxisOptions())
    _validate_axis_options(options.left_y_axis)
    _validate_axis_options(right)
    all(count -> 2 <= count <= 1_000, (options.x_tick_count, options.left_y_axis.tick_count, right.tick_count)) ||
        throw(ArgumentError("Tick counts must be between 2 and 1000."))
    options.width > 0 && options.height > 0 || throw(ArgumentError("Chart width and height must be positive."))
    !isnothing(options.x_date_format) && isnothing(_strftime_items(something(options.x_date_format))) &&
        throw(ArgumentError("Invalid x-axis date format $(repr(options.x_date_format)); supported items are $(join(_STRFTIME_ITEMS, ", "))."))
    for reference in options.reference_lines
        isfinite(reference.value) || throw(ArgumentError("Reference lines must be finite."))
        _validate_side(reference.axis, "Reference line")
        include!(bounds[_side_index(reference.axis)], reference.value)
    end
    return bounds
end

struct LegendEntry
    label::String
    color::String
    symbol::Symbol
    size::Float64
    opacity::Float64
end

function _series_color!(color::Union{Nothing,String}, options::ChartOptions, index::Base.RefValue{Int})::String
    isnothing(color) || return color
    palette = options.theme.series_palette
    selected = palette[mod(index[], length(palette)) + 1]
    index[] += 1
    return selected
end

function _append_reference_legend!(legend::Vector{LegendEntry}, options::ChartOptions)
    for reference in options.reference_lines
        isnothing(reference.label) && continue
        push!(legend, LegendEntry(something(reference.label), something(reference.color, options.theme.reference), :line,
            1.0, options.theme.reference_opacity))
    end
    return legend
end

# Canvas

mutable struct Canvas
    options::ChartOptions
    left_axis::Axis
    right_axis::Union{Nothing,Axis}
    height::Int
    top::Float64
    bottom::Float64
    right::Float64
    x_padding::Float64
    legend_y::Float64
    legend_columns::Int
    legend_rows::Int
end

function Canvas(options::ChartOptions, bounds::Vector{Bounds}, series_count::Int, bars::Bool, rotated::Bool)
    left_axis = Axis(bounds[1], options.left_y_axis, bars)
    right_axis = if isempty_bounds(bounds[2])
        isnothing(options.right_y_axis) ||
            throw(ArgumentError("Right-axis options require right-axis data or references."))
        nothing
    else
        Axis(bounds[2], something(options.right_y_axis, AxisOptions()), bars)
    end
    legend_columns = isnothing(options.legend) ? 0 : min(something(options.legend), series_count)
    legend_rows = legend_columns == 0 ? 0 : cld(series_count, legend_columns)
    height = options.height + max(legend_rows - 2, 0) * LEGEND_ROW_HEIGHT
    legend_y = 36.0 + (isnothing(options.title) ? 0.0 : 34.0) + (isnothing(options.subtitle) ? 0.0 : 28.0)
    top = legend_y + legend_rows * LEGEND_ROW_HEIGHT + 4.0
    bottom = height - (rotated ? 145.0 : 55.0) - (isnothing(options.x_label) ? 0.0 : 25.0)
    right = options.width - (isnothing(right_axis) ? 32.0 : 100.0)
    right > LEFT && bottom > top || throw(ArgumentError("Canvas is too small for its labels and legend."))
    return Canvas(options, left_axis, right_axis, height, top, bottom, right, 0.0, legend_y, legend_columns, legend_rows)
end

_axis(canvas::Canvas, side::Symbol) = side == :right ? something(canvas.right_axis, canvas.left_axis) : canvas.left_axis
_y(canvas::Canvas, value::Float64, side::Symbol) =
    canvas.top + (canvas.bottom - canvas.top) * (1.0 - _axis_fraction(_axis(canvas, side), value))
_x(canvas::Canvas, point::XPoint, start::XPoint, stop::XPoint) =
    LEFT + canvas.x_padding + (canvas.right - LEFT - 2.0 * canvas.x_padding) * _fraction(point, start, stop)

function _start!(io::IO, canvas::Canvas, kind::AbstractString, legend::Vector{LegendEntry})
    options = canvas.options
    theme = options.theme
    println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    print(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$(options.width)\" height=\"$(canvas.height)\" ",
        "viewBox=\"0 0 $(options.width) $(canvas.height)\" role=\"img\" data-chart-type=\"$(kind)\"")
    for (prefix, axis) in (("y", canvas.left_axis), ("y-right", canvas.right_axis))
        isnothing(axis) && continue
        scale = axis.options.scale == :linear ? "linear" : "log10"
        print(io, " data-$(prefix)-scale=\"$(scale)\" data-$(prefix)-lower=\"$(_display(axis.lower))\" ",
            "data-$(prefix)-upper=\"$(_display(axis.upper))\"")
    end
    println(io, ">\n<title>$(escape_xml(something(options.title, "Chart")))</title>")
    isnothing(options.subtitle) || println(io, "<desc>$(escape_xml(something(options.subtitle)))</desc>")
    println(io, "<rect width=\"100%\" height=\"100%\" fill=\"$(escape_xml(theme.canvas))\"/>")
    println(io, "<defs><clipPath id=\"plot-clip\"><rect x=\"$(_display(LEFT))\" y=\"$(_display(canvas.top))\" ",
        "width=\"$(_display(canvas.right - LEFT))\" height=\"$(_display(canvas.bottom - canvas.top))\"/></clipPath></defs>")
    println(io, "<g font-family=\"$(escape_xml(theme.font_family))\">")
    text_y = 42
    if !isnothing(options.title)
        println(io, "<text x=\"48\" y=\"$(text_y)\" fill=\"$(escape_xml(theme.text))\" font-size=\"28\" ",
            "font-weight=\"650\">$(escape_xml(something(options.title)))</text>")
        text_y += 28
    end
    isnothing(options.subtitle) || println(io, "<text x=\"48\" y=\"$(text_y)\" fill=\"$(escape_xml(theme.muted_text))\" ",
        "font-size=\"16\">$(escape_xml(something(options.subtitle)))</text>")
    _legend!(io, canvas, legend)
    _y_axes!(io, canvas)
    isnothing(options.x_label) || println(io, "<text x=\"$(_display((LEFT + canvas.right) / 2.0))\" ",
        "y=\"$(canvas.height - 18)\" fill=\"$(escape_xml(theme.muted_text))\" font-size=\"16\" ",
        "text-anchor=\"middle\">$(escape_xml(something(options.x_label)))</text>")
    return nothing
end

function _legend!(io::IO, canvas::Canvas, entries::Vector{LegendEntry})
    canvas.legend_columns == 0 && return nothing
    options = canvas.options
    theme = options.theme
    slot = (options.width - 96.0) / canvas.legend_columns
    println(io, "<rect x=\"40\" y=\"$(_display(canvas.legend_y - 17.0))\" width=\"$(options.width - 80)\" ",
        "height=\"$(canvas.legend_rows * LEGEND_ROW_HEIGHT + 8)\" rx=\"4\" fill=\"$(escape_xml(theme.legend_background))\" ",
        "fill-opacity=\"$(_display(theme.legend_opacity))\"/>")
    column = 0
    y = canvas.legend_y
    for entry in entries
        x = 48.0 + column * slot
        if entry.symbol == :bar
            println(io, "<rect x=\"$(_display(x))\" y=\"$(_display(y - 7.0))\" width=\"25\" height=\"10\" ",
                "fill=\"$(escape_xml(entry.color))\" fill-opacity=\"$(_display(entry.opacity))\"/>")
        elseif entry.symbol == :line
            println(io, "<path d=\"M $(_display(x)) $(_display(y)) h 25\" stroke=\"$(escape_xml(entry.color))\" ",
                "stroke-width=\"$(_debug(entry.size))\" stroke-opacity=\"$(_display(entry.opacity))\"/>")
        else
            println(io, "<circle cx=\"$(_display(x + 12.5))\" cy=\"$(_display(y))\" r=\"$(_display(entry.size))\" ",
                "fill=\"$(escape_xml(entry.color))\" fill-opacity=\"$(_display(entry.opacity))\"/>")
        end
        println(io, "<text x=\"$(_display(x + 33.0))\" y=\"$(_display(y + 5.0))\" fill=\"$(escape_xml(theme.text))\" ",
            "font-size=\"16\">$(escape_xml(entry.label))</text>")
        column += 1
        if column == canvas.legend_columns
            column = 0
            y += LEGEND_ROW_HEIGHT
        end
    end
    return nothing
end

function _y_axes!(io::IO, canvas::Canvas)
    theme = canvas.options.theme
    println(io, "<path d=\"M $(_display(LEFT)) $(_display(canvas.top)) V $(_display(canvas.bottom)) H $(_display(canvas.right))\" ",
        "fill=\"none\" stroke=\"$(escape_xml(theme.axis))\" stroke-width=\"0.8\"/>")
    for side in AXIS_SIDES
        side == :right && isnothing(canvas.right_axis) && continue
        axis = _axis(canvas, side)
        x, direction, anchor = side == :left ? (LEFT, -1.0, "end") : (canvas.right, 1.0, "start")
        side == :right && println(io, "<path d=\"M $(_display(x)) $(_display(canvas.top)) V $(_display(canvas.bottom))\" ",
            "stroke=\"$(escape_xml(theme.axis))\" stroke-width=\"0.8\"/>")
        for tick in _ticks(axis)
            y = _y(canvas, tick, side)
            label = axis.options.format == :percentage ? number_label(tick * 100.0) * "%" : number_label(tick)
            theme.grid && side == :left && println(io, "<path class=\"grid\" d=\"M $(_display(LEFT)) $(_fixed2(y)) ",
                "H $(_display(canvas.right))\" stroke=\"$(escape_xml(theme.axis))\" stroke-opacity=\"0.2\"/>")
            println(io, "<path d=\"M $(_display(x)) $(_fixed2(y)) h $(_display(direction * 5.0))\" ",
                "stroke=\"$(escape_xml(theme.axis))\" stroke-width=\"0.8\"/>")
            println(io, "<text x=\"$(_display(x + direction * 10.0))\" y=\"$(_fixed2(y + 5.0))\" ",
                "fill=\"$(escape_xml(theme.muted_text))\" font-size=\"15\" text-anchor=\"$(anchor)\">$(label)</text>")
        end
        if !isnothing(axis.options.label)
            label = something(axis.options.label)
            axis.options.scale == :logarithmic && !endswith(label, "(log scale)") && (label = "$(label) (log scale)")
            label_x = side == :left ? 22.0 : canvas.options.width - 22.0
            y = (canvas.top + canvas.bottom) / 2.0
            println(io, "<text x=\"$(_display(label_x))\" y=\"$(_display(y))\" fill=\"$(escape_xml(theme.muted_text))\" ",
                "font-size=\"16\" text-anchor=\"middle\" transform=\"rotate($(_display(direction * 90.0)) ",
                "$(_display(label_x)) $(_display(y)))\">$(escape_xml(label))</text>")
        end
    end
    return nothing
end

function _references!(io::IO, canvas::Canvas)
    for reference in canvas.options.reference_lines
        side = reference.axis == :left ? "left" : "right"
        print(io, "<path class=\"reference-line\" data-y-axis=\"$(side)\" data-value=\"$(_display(reference.value))\" ",
            "d=\"M $(_display(LEFT)) $(_fixed2(_y(canvas, reference.value, reference.axis))) H $(_display(canvas.right))\" ",
            "stroke=\"$(escape_xml(something(reference.color, canvas.options.theme.reference)))\" stroke-width=\"1\" ",
            "stroke-opacity=\"$(_display(canvas.options.theme.reference_opacity))\">")
        isnothing(reference.label) || print(io, "<title>$(escape_xml(something(reference.label)))</title>")
        println(io, "</path>")
    end
    return nothing
end

function _zero_lines!(io::IO, canvas::Canvas)
    for side in AXIS_SIDES
        side == :right && isnothing(canvas.right_axis) && continue
        axis = _axis(canvas, side)
        zero = clamp(0.0, axis.lower, axis.upper)
        println(io, "<path class=\"zero-line\" d=\"M $(_display(LEFT)) $(_fixed2(_y(canvas, zero, side))) ",
            "H $(_display(canvas.right))\" stroke=\"$(escape_xml(canvas.options.theme.axis))\" stroke-width=\"0.8\"/>")
    end
    return nothing
end

function _x_tick!(io::IO, canvas::Canvas, x::Float64, label::AbstractString, anchor::AbstractString, rotate::Bool)
    y = canvas.bottom + 25.0
    println(io, "<path d=\"M $(_fixed2(x)) $(_display(canvas.bottom)) v 5\" stroke=\"$(escape_xml(canvas.options.theme.axis))\" ",
        "stroke-width=\"0.8\"/>")
    print(io, "<text x=\"$(_fixed2(x))\" y=\"$(_display(y))\" fill=\"$(escape_xml(canvas.options.theme.muted_text))\" ",
        "font-size=\"15\" text-anchor=\"$(anchor)\"")
    rotate && print(io, " transform=\"rotate(-35 $(_fixed2(x)) $(_display(y)))\"")
    println(io, ">$(escape_xml(label))</text>")
    return nothing
end

function _date_label(time::DateTime, span::Millisecond, format::Union{Nothing,String})::String
    selected = if !isnothing(format)
        something(format)
    elseif span < Second(1)
        "%H:%M:%S%.9f"
    elseif span < Minute(1)
        "%H:%M:%S"
    elseif span < Day(2)
        "%Y-%m-%d %H:%M"
    elseif span < Day(60)
        "%Y-%m-%d"
    elseif span < Day(730)
        "%Y-%m"
    else
        "%Y"
    end
    return _strftime(time, selected)
end

function _continuous_x_ticks!(io::IO, canvas::Canvas, points::Vector{XPoint})
    start, stop = first(points), last(points)
    span = start.temporal && stop.temporal ? stop.time - start.time : Millisecond(0)
    indices = if span >= Day(730) && isnothing(canvas.options.x_date_format)
        candidates = [index for (index, point) in enumerate(points)
                      if point.temporal && (index == 1 || (points[index - 1].temporal && year(points[index - 1].time) != year(point.time)))]
        [candidates[index + 1] for index in _tick_indices(length(candidates), canvas.options.x_tick_count)]
    else
        [index + 1 for index in _tick_indices(length(points), canvas.options.x_tick_count)]
    end
    previous_label = ""
    for index in indices
        point = points[index]
        label = point.temporal ? _date_label(point.time, span, canvas.options.x_date_format) : number_label(point.value)
        label == previous_label && continue
        anchor = index == 1 && length(points) > 1 ? "start" : index == length(points) && length(points) > 1 ? "end" : "middle"
        _x_tick!(io, canvas, _x(canvas, point, start, stop), label, anchor, false)
        previous_label = label
    end
    return nothing
end

function _xy_chart_bounds(series, options::ChartOptions)
    bounds = _validate_options(options)
    points = XPoint[]
    numeric = nothing
    has_left_series = false
    for item in series
        _validate_side(item.axis, "Series '$(item.label)'")
        is_numeric = _is_numeric_x(item.x)
        (is_numeric || _is_temporal_x(item.x)) && !isempty(item.x) && length(item.x) == length(item.values) &&
            (isnothing(numeric) || numeric == is_numeric) ||
            throw(ArgumentError("Series '$(item.label)' requires aligned nonempty x/y vectors with one shared x-axis type."))
        numeric = is_numeric
        is_numeric && !isnothing(options.x_date_format) &&
            throw(ArgumentError("Date formatting requires temporal x values."))
        has_left_series |= item.axis == :left
        for index in eachindex(item.values)
            sampled = _sample(item.x, item.values, index)
            isnothing(sampled) && continue
            push!(points, sampled[1])
            include!(bounds[_side_index(item.axis)], sampled[2])
        end
    end
    has_left_series && !isempty(points) ||
        throw(ArgumentError("Chart requires a left-axis series and finite x/y pairs."))
    sort!(points; lt=(left, right) -> _compare(left, right) < 0)
    unique_points = XPoint[]
    for point in points
        isempty(unique_points) || _compare(last(unique_points), point) != 0 || continue
        push!(unique_points, point)
    end
    return bounds, unique_points
end

function _draw_line!(io::IO, canvas::Canvas, line::LineSeries, color::String, start::XPoint, stop::XPoint)
    any(index -> !isnothing(_sample(line.x, line.values, index)), eachindex(line.values)) || return nothing
    side = line.axis == :left ? "left" : "right"
    print(io, "<path class=\"series\" data-y-axis=\"$(side)\" d=\"")
    in_segment = false
    for index in eachindex(line.values)
        sampled = _sample(line.x, line.values, index)
        if isnothing(sampled)
            in_segment = false
            continue
        end
        print(io, in_segment ? " L" : " M", " ", _fixed2(_x(canvas, sampled[1], start, stop)), " ",
            _fixed2(_y(canvas, sampled[2], line.axis)))
        in_segment = true
    end
    println(io, "\" fill=\"none\" stroke=\"$(escape_xml(color))\" stroke-width=\"$(_debug(line.width))\" ",
        "stroke-opacity=\"$(_display(canvas.options.theme.series_opacity))\" stroke-linejoin=\"round\" stroke-linecap=\"round\" ",
        "vector-effect=\"non-scaling-stroke\"><title>$(escape_xml(line.label))</title></path>")
    for index in eachindex(line.values)
        sampled = _sample(line.x, line.values, index)
        isnothing(sampled) && continue
        (index == 1 || isnothing(_sample(line.x, line.values, index - 1))) && isnothing(_sample(line.x, line.values, index + 1)) ||
            continue
        println(io, "<circle class=\"line-point\" data-y-axis=\"$(side)\" cx=\"$(_fixed2(_x(canvas, sampled[1], start, stop)))\" ",
            "cy=\"$(_fixed2(_y(canvas, sampled[2], line.axis)))\" r=\"2.4\" fill=\"$(escape_xml(color))\" ",
            "fill-opacity=\"$(_display(canvas.options.theme.series_opacity))\"><title>$(escape_xml(line.label))</title></circle>")
    end
    return nothing
end

"""
    render_svg_line_chart(series, options) -> String

Compose a self-contained SVG with numeric or temporal x values and up to two y axes. Throws an
`ArgumentError` for invalid options, mixed numeric/temporal x values, misaligned samples, no finite
samples, or nonpositive finite values on a logarithmic axis.
"""
function render_svg_line_chart(series::AbstractVector{LineSeries}, options::ChartOptions)::String
    bounds, points = _xy_chart_bounds(series, options)
    legend = LegendEntry[]
    palette_index = Ref(0)
    for line in series
        isfinite(line.width) && line.width > 0 || throw(ArgumentError("Line widths must be finite and positive."))
        push!(legend, LegendEntry(line.label, _series_color!(line.color, options, palette_index), :line, line.width,
            options.theme.series_opacity))
    end
    _append_reference_legend!(legend, options)
    canvas = Canvas(options, bounds, length(legend), false, false)
    io = IOBuffer()
    _start!(io, canvas, "line", legend)
    _continuous_x_ticks!(io, canvas, points)
    println(io, "<g clip-path=\"url(#plot-clip)\">")
    _references!(io, canvas)
    for (line, entry) in zip(series, legend)
        _draw_line!(io, canvas, line, entry.color, first(points), last(points))
    end
    println(io, "</g></g></svg>")
    return String(take!(io))
end

function _validate_scatter_style(series::ScatterSeries)
    isfinite(series.radius) && series.radius > 0 &&
        (isnothing(series.opacity) || (isfinite(something(series.opacity)) && 0.0 <= something(series.opacity) <= 1.0)) ||
        throw(ArgumentError("Scatter series '$(series.label)' requires a positive finite radius and opacity in [0, 1]."))
    if !isnothing(series.labels)
        labels = something(series.labels)
        length(labels) == length(series.values) ||
            throw(ArgumentError("Scatter labels for '$(series.label)' must align with samples."))
        all(label -> isnothing(label) || all(isfinite, label.offset), labels) ||
            throw(ArgumentError("Scatter label offsets must be finite."))
    end
    return nothing
end

function _draw_scatter_series!(io::IO, canvas::Canvas, series::ScatterSeries, entry::LegendEntry, start::XPoint, stop::XPoint)
    side = series.axis == :left ? "left" : "right"
    println(io, "<g clip-path=\"url(#plot-clip)\">")
    for index in eachindex(series.values)
        sampled = _sample(series.x, series.values, index)
        isnothing(sampled) && continue
        point_label = isnothing(series.labels) ? nothing : something(series.labels)[index]
        label = isnothing(point_label) ? series.label : point_label.text
        println(io, "<circle class=\"scatter-point\" data-y-axis=\"$(side)\" cx=\"$(_fixed2(_x(canvas, sampled[1], start, stop)))\" ",
            "cy=\"$(_fixed2(_y(canvas, sampled[2], series.axis)))\" r=\"$(_display(series.radius))\" fill=\"$(escape_xml(entry.color))\" ",
            "fill-opacity=\"$(_display(entry.opacity))\"><title>$(escape_xml(label))</title></circle>")
    end
    println(io, "</g>")
    isnothing(series.labels) && return nothing
    axis = _axis(canvas, series.axis)
    for (index, label) in enumerate(something(series.labels))
        isnothing(label) && continue
        sampled = _sample(series.x, series.values, index)
        isnothing(sampled) && continue
        axis.lower <= sampled[2] <= axis.upper || continue
        println(io, "<text class=\"point-label\" x=\"$(_fixed2(_x(canvas, sampled[1], start, stop) + label.offset[1]))\" ",
            "y=\"$(_fixed2(_y(canvas, sampled[2], series.axis) + label.offset[2]))\" fill=\"$(escape_xml(canvas.options.theme.text))\" ",
            "font-size=\"14\">$(escape_xml(label.text))</text>")
    end
    return nothing
end

"""
    render_svg_scatter_chart(series, options) -> String

Compose scatter markers with numeric or temporal x values and up to two y axes. Marker styles apply
per series; labels use caller-supplied offsets without collision avoidance or axis expansion.
"""
function render_svg_scatter_chart(series::AbstractVector{ScatterSeries}, options::ChartOptions)::String
    bounds, points = _xy_chart_bounds(series, options)
    legend = LegendEntry[]
    palette_index = Ref(0)
    largest_radius = 0.0
    for item in series
        _validate_scatter_style(item)
        largest_radius = max(largest_radius, item.radius)
        push!(legend, LegendEntry(item.label, _series_color!(item.color, options, palette_index), :circle, min(item.radius, 10.0),
            something(item.opacity, options.theme.series_opacity)))
    end
    _append_reference_legend!(legend, options)
    canvas = Canvas(options, bounds, length(legend), false, false)
    canvas.x_padding = largest_radius + 2.0
    canvas.x_padding < (canvas.right - LEFT) / 2.0 ||
        throw(ArgumentError("Scatter marker radius leaves no room for the x-axis range."))
    io = IOBuffer()
    _start!(io, canvas, "scatter", legend)
    _continuous_x_ticks!(io, canvas, points)
    println(io, "<g clip-path=\"url(#plot-clip)\">")
    _references!(io, canvas)
    println(io, "</g>")
    for (item, entry) in zip(series, legend)
        _draw_scatter_series!(io, canvas, item, entry, first(points), last(points))
    end
    println(io, "</g></svg>")
    return String(take!(io))
end

function _draw_bar_rectangle!(io::IO, canvas::Canvas, horizontal::Tuple{Float64,Float64}, vertical::Tuple{Float64,Float64},
    axis::Symbol, entry::LegendEntry, title::AbstractString)
    lower_y = _y(canvas, vertical[1], axis)
    upper_y = _y(canvas, vertical[2], axis)
    side = axis == :left ? "left" : "right"
    println(io, "<rect class=\"bar\" data-y-axis=\"$(side)\" x=\"$(_fixed2(horizontal[1]))\" y=\"$(_fixed2(min(lower_y, upper_y)))\" ",
        "width=\"$(_fixed2(horizontal[2] - horizontal[1]))\" height=\"$(_fixed2(abs(upper_y - lower_y)))\" ",
        "fill=\"$(escape_xml(entry.color))\" fill-opacity=\"$(_display(entry.opacity))\"><title>$(title)</title></rect>")
    return nothing
end

function _bar_bounds(categories::AbstractVector{<:AbstractString}, series::AbstractVector{BarSeries}, options::BarChartOptions)
    bounds = _validate_options(options.chart)
    !isempty(categories) && !isempty(series) && any(item -> item.axis == :left, series) ||
        throw(ArgumentError("Bar chart requires categories and a left-axis series."))
    isfinite(options.bar_width) && 0.0 < options.bar_width <= 1.0 && isnothing(options.chart.x_date_format) ||
        throw(ArgumentError("Bar width must be in (0, 1]; categories cannot use date formatting."))
    for item in series
        _validate_side(item.axis, "Bar series '$(item.label)'")
        length(item.values) == length(categories) && all(isfinite, item.values) ||
            throw(ArgumentError("Bar series '$(item.label)' requires one finite value per category."))
        side_bounds = bounds[_side_index(item.axis)]
        foreach(value -> include!(side_bounds, value), item.values)
        isnothing(item.intervals) && continue
        intervals = something(item.intervals)
        length(intervals) == length(categories) || throw(ArgumentError("Bar intervals must align with categories."))
        for (lower, upper) in intervals
            isfinite(lower) && isfinite(upper) && lower <= upper ||
                throw(ArgumentError("Bar intervals must be finite and ordered."))
            include!(side_bounds, lower)
            include!(side_bounds, upper)
        end
    end
    return bounds
end

"""
    render_svg_bar_chart(categories, series, options) -> String

Compose categorical bars with a zero baseline, optional intervals, and an optional right axis.
"""
function render_svg_bar_chart(categories::AbstractVector{<:AbstractString}, series::AbstractVector{BarSeries},
    options::BarChartOptions)::String
    chart_options = options.chart
    bounds = _bar_bounds(categories, series, options)
    palette_index = Ref(0)
    legend = [LegendEntry(item.label, _series_color!(item.color, chart_options, palette_index), :bar, 0.0,
        chart_options.theme.series_opacity) for item in series]
    rotated = something(options.rotate_labels, length(categories) > 8 || any(label -> length(label) > 14, categories))
    _append_reference_legend!(legend, chart_options)
    canvas = Canvas(chart_options, bounds, length(legend), true, rotated)
    slot = (canvas.right - LEFT) / length(categories)
    bar_width = slot * options.bar_width / length(series)
    io = IOBuffer()
    _start!(io, canvas, "bar", legend)
    println(io, "<g clip-path=\"url(#plot-clip)\">")
    _references!(io, canvas)
    _zero_lines!(io, canvas)
    category_x = LEFT + slot / 2.0
    for (category_index, category) in enumerate(categories)
        center = category_x - slot * options.bar_width / 2.0 + bar_width / 2.0
        for (item, entry) in zip(series, legend)
            axis = _axis(canvas, item.axis)
            zero = clamp(0.0, axis.lower, axis.upper)
            value = item.values[category_index]
            _draw_bar_rectangle!(io, canvas, (center - bar_width / 2.0, center + bar_width / 2.0), (zero, value), item.axis, entry,
                "$(escape_xml(item.label)): $(escape_xml(category)): $(number_label(value))")
            if !isnothing(item.intervals)
                lower, upper = something(item.intervals)[category_index]
                lower_y, upper_y = _y(canvas, lower, item.axis), _y(canvas, upper, item.axis)
                side = item.axis == :left ? "left" : "right"
                println(io, "<path class=\"error-bar\" data-y-axis=\"$(side)\" d=\"M $(_fixed2(center)) $(_fixed2(lower_y)) ",
                    "V $(_fixed2(upper_y)) M $(_fixed2(center - 5.0)) $(_fixed2(lower_y)) H $(_fixed2(center + 5.0)) ",
                    "M $(_fixed2(center - 5.0)) $(_fixed2(upper_y)) H $(_fixed2(center + 5.0))\" fill=\"none\" ",
                    "stroke=\"$(escape_xml(canvas.options.theme.text))\" stroke-width=\"1.5\"><title>$(escape_xml(category)) ",
                    "interval: [$(number_label(lower)), $(number_label(upper))]</title></path>")
            end
            center += bar_width
        end
        category_x += slot
    end
    println(io, "</g>")
    center = LEFT + slot / 2.0
    for category in categories
        _x_tick!(io, canvas, center, category, rotated ? "end" : "middle", rotated)
        center += slot
    end
    println(io, "</g></svg>")
    return String(take!(io))
end

function _interval_boundaries(boundaries::AbstractVector)::Vector{XPoint}
    points = XPoint[]
    for index in eachindex(boundaries)
        point = _x_point(boundaries, index)
        isnothing(point) && throw(ArgumentError("Bar boundaries must be finite."))
        if !isempty(points)
            previous = last(points)
            ordered = point.temporal ? _compare(previous, something(point)) < 0 : previous.value < point.value
            ordered || throw(ArgumentError("Bar boundaries must be strictly increasing."))
        end
        push!(points, something(point))
    end
    return points
end

function _stacked_bounds(boundaries::AbstractVector, series::AbstractVector{StackedBarSeries}, options::ChartOptions)
    bounds = _validate_options(options)
    length(boundaries) >= 2 && any(item -> item.axis == :left, series) ||
        throw(ArgumentError("Stacked bars require at least two boundaries and a left-axis series."))
    _is_numeric_x(boundaries) || _is_temporal_x(boundaries) ||
        throw(ArgumentError("Stacked bar boundaries must be numeric, DateTime, or Date values."))
    _is_numeric_x(boundaries) && !isnothing(options.x_date_format) &&
        throw(ArgumentError("Date formatting requires temporal x values."))
    for item in series
        _validate_side(item.axis, "Stacked series '$(item.label)'")
        length(item.values) == length(boundaries) - 1 && all(isfinite, item.values) ||
            throw(ArgumentError("Stacked series '$(item.label)' requires one finite value per interval."))
    end
    for index in 1:(length(boundaries) - 1)
        totals = zeros(2, 2)
        for item in series
            value = item.values[index]
            side = _side_index(item.axis)
            sign = value < 0.0 ? 2 : 1
            totals[side, sign] += value
            isfinite(totals[side, sign]) ||
                throw(ArgumentError("Stack total overflowed at interval $(index - 1) for series '$(item.label)'."))
            include!(bounds[side], totals[side, sign])
        end
    end
    return bounds
end

"""
    render_svg_stacked_bar_chart(boundaries, series, options) -> String

Compose stacked bars over numeric or temporal intervals. Supply `n + 1` strictly increasing
boundaries for `n` values per series; bars fill each interval and touch their neighbors. Positive
and negative values stack independently from zero, in series order, on each axis.
"""
function render_svg_stacked_bar_chart(boundaries::AbstractVector, series::AbstractVector{StackedBarSeries},
    options::ChartOptions)::String
    bounds = _stacked_bounds(boundaries, series, options)
    points = _interval_boundaries(boundaries)
    palette_index = Ref(0)
    legend = [LegendEntry(item.label, _series_color!(item.color, options, palette_index), :bar, 0.0, options.theme.series_opacity)
              for item in series]
    _append_reference_legend!(legend, options)
    canvas = Canvas(options, bounds, length(legend), true, false)
    io = IOBuffer()
    _start!(io, canvas, "stacked-bar", legend)
    _continuous_x_ticks!(io, canvas, points)
    println(io, "<g clip-path=\"url(#plot-clip)\">")
    start, stop = first(points), last(points)
    for index in 1:(length(points) - 1)
        horizontal = (_x(canvas, points[index], start, stop), _x(canvas, points[index + 1], start, stop))
        totals = zeros(2, 2)
        for (item, entry) in zip(series, legend)
            value = item.values[index]
            side, sign = _side_index(item.axis), value < 0.0 ? 2 : 1
            bottom = totals[side, sign]
            totals[side, sign] += value
            value == 0.0 && continue
            _draw_bar_rectangle!(io, canvas, horizontal, (bottom, totals[side, sign]), item.axis, entry,
                "$(escape_xml(item.label)): $(number_label(value))")
        end
    end
    _zero_lines!(io, canvas)
    _references!(io, canvas)
    println(io, "</g></g></svg>")
    return String(take!(io))
end

function _validate_chart_path(path::AbstractString)
    !isempty(basename(path)) && endswith(path, ".svg") ||
        throw(ArgumentError("Chart path '$(path)' must use a .svg extension."))
    return nothing
end

function _write_svg(path::AbstractString, svg::String)
    target = abspath(path)
    mkpath(dirname(target))
    temporary = target * ".tmp"
    write(temporary, svg)
    mv(temporary, target; force=true)
    return nothing
end

"""
    write_svg_line_chart(path, series, options)

Write a line chart with atomic replacement, creating parent directories. The extension must be
`.svg`.
"""
function write_svg_line_chart(path::AbstractString, series::AbstractVector{LineSeries}, options::ChartOptions)::Nothing
    _validate_chart_path(path)
    _write_svg(path, render_svg_line_chart(series, options))
    return nothing
end

"""
    write_svg_scatter_chart(path, series, options)

Write a scatter chart with atomic replacement, creating parent directories.
"""
function write_svg_scatter_chart(path::AbstractString, series::AbstractVector{ScatterSeries}, options::ChartOptions)::Nothing
    _validate_chart_path(path)
    _write_svg(path, render_svg_scatter_chart(series, options))
    return nothing
end

"""
    write_svg_bar_chart(path, categories, series, options)

Write a categorical bar chart with atomic replacement, creating parent directories.
"""
function write_svg_bar_chart(path::AbstractString, categories::AbstractVector{<:AbstractString},
    series::AbstractVector{BarSeries}, options::BarChartOptions)::Nothing
    _validate_chart_path(path)
    _write_svg(path, render_svg_bar_chart(categories, series, options))
    return nothing
end

"""
    write_svg_stacked_bar_chart(path, boundaries, series, options)

Write a stacked interval bar chart with atomic replacement, creating parent directories.
"""
function write_svg_stacked_bar_chart(path::AbstractString, boundaries::AbstractVector,
    series::AbstractVector{StackedBarSeries}, options::ChartOptions)::Nothing
    _validate_chart_path(path)
    _write_svg(path, render_svg_stacked_bar_chart(boundaries, series, options))
    return nothing
end

end # module Charts
