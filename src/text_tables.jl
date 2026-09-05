# Small text-only table renderer shared by account and exchange-rate displays.
# Cells are formatted only for the retained rows, even for long trade histories.

const _TEXT_POSITIVE = (17, 191, 17)
const _TEXT_NEGATIVE = (221, 0, 0)
const _TEXT_LONG = (221, 0, 221)
const _TEXT_SHORT = (221, 221, 0)

function _print_styled(
    io::IO,
    text::AbstractString
    ;
    color=nothing,
    bold::Bool=false,
)
    styled = get(io, :color, false) && (color !== nothing || bold)

    if styled
        bold && print(io, "\e[1m")
        color !== nothing && print(io, "\e[38;2;", color[1], ';', color[2], ';', color[3], 'm')
    end

    print(io, text)
    styled && print(io, "\e[0m")
    return nothing
end

function _table_text(value)
    return replace(string(value), '\n' => "\\n", '\r' => "\\r", '\t' => "\\t", '\e' => "\\e")
end

function _clip_table_text(text::AbstractString, width::Int)
    textwidth(text) <= width && return text
    width <= 0 && return ""
    used = 0
    last = 0

    for index in eachindex(text)
        used += textwidth(text[index])
        used > width - 1 && break
        last = index
    end

    return string(SubString(text, 1, last), '…')
end

function _table_rule(io::IO, widths, edges::AbstractString)
    left, middle, right = collect(edges)
    print(io, left)

    for (j, width) in enumerate(widths)
        print(io, repeat("─", width + 2), j == length(widths) ? right : middle)
    end

    println(io)
end

function _table_line(
    io::IO,
    cells,
    widths
    ;
    colors=nothing,
    bold::Bool=false,
)
    print(io, '│')

    for (j, width) in enumerate(widths)
        text = _clip_table_text(cells[j], width)
        print(io, ' ', repeat(" ", width - textwidth(text)))
        _print_styled(io, text; color=colors === nothing ? nothing : colors[j], bold)
        print(io, " │")
    end

    println(io)
end

"""
Render a text table with right-aligned cells and head/tail row cropping.
Negative `max_rows` shows every row; zero shows only the header and omission count.
The `cell` callback returns `(formatted_value, rgb_color_or_nothing)`.
"""
function _print_text_table(
    io::IO,
    labels,
    row_count::Int
    ;
    cell,
    max_rows::Int=-1,
)
    isempty(labels) && return nothing
    count = max_rows < 0 ? row_count : min(row_count, max_rows)
    head = cld(count, 2)
    rows = count == row_count ? collect(1:row_count) : vcat(1:head, (row_count - fld(count, 2) + 1):row_count)
    headers = _table_text.(labels)
    cells = Matrix{String}(undef, count, length(labels))
    colors = Matrix{Union{Nothing,NTuple{3,Int}}}(nothing, count, length(labels))

    for (ri, i) in enumerate(rows), j in eachindex(labels)
        value, color = cell(i, j)
        cells[ri, j] = _table_text(value)
        colors[ri, j] = color
    end

    widths = [max(1, textwidth(headers[j]), maximum(textwidth, view(cells, :, j); init=0)) for j in eachindex(labels)]
    display_width = max(0, displaysize(io)[2])

    # A complete single-column frame needs at least five character cells.
    if display_width < 5
        display_width > 0 && println(io, '…')
        return nothing
    end

    if sum(widths) + 3 * length(widths) + 1 > display_width
        # A data column plus an ellipsis column needs at least nine cells.
        if display_width < 9
            println(io, '…')
            return nothing
        end

        budget = display_width - 5
        visible = 0

        for width in widths
            budget < 4 && break
            visible += 1
            widths[visible] = min(width, budget - 3)
            budget -= widths[visible] + 3
        end

        resize!(widths, visible)
        push!(widths, 1)
        headers = vcat(headers[1:visible], "…")
        cells = hcat(cells[:, 1:visible], fill("…", count))
        colors = hcat(colors[:, 1:visible], fill(nothing, count))
    end

    _table_rule(io, widths, "┌┬┐")
    _table_line(io, headers, widths; bold=true)
    _table_rule(io, widths, "├┼┤")

    for ri in eachindex(rows)
        _table_line(io, view(cells, ri, :), widths; colors=view(colors, ri, :))

        if count < row_count && ri == head
            _table_line(io, fill("⋮", length(widths)), widths)
        end
    end

    _table_rule(io, widths, "└┴┘")

    if count < row_count
        omitted = row_count - count
        println(io, _clip_table_text("$omitted $(omitted == 1 ? "row" : "rows") omitted", display_width))
    end

    return nothing
end

function _print_record_table(
    io::IO,
    records,
    columns
    ;
    max_rows::Int=-1,
    value_columns=(),
    quantity_columns=(),
)
    function cell(i, j)
        column = columns[j]
        record = records[i]
        value = column[:val](record)
        name = column[:name]
        color = nothing

        if name in value_columns
            color = value > 0 ? _TEXT_POSITIVE : value < 0 ? _TEXT_NEGATIVE : nothing
        elseif name in quantity_columns
            color = value > 0 ? _TEXT_LONG : value < 0 ? _TEXT_SHORT : nothing
        end

        return column[:fmt](record, value), color
    end

    _print_text_table(io, [c[:name] for c in columns], length(records); cell, max_rows)
end
