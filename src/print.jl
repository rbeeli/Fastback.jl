using PrettyTables
using Printf
using DataFrames

# --------------- Position ---------------

function print_positions(
    positions::Vector{Position};
    max_print=25,
    volume_digits=1,
    price_digits=2,
    data_renderer::Union{Function, Nothing}=nothing,
    kwargs...
)
    print_positions(
        stdout,
        positions;
        max_print,
        volume_digits,
        price_digits,
        data_renderer,
        kwargs...)
end

function print_positions(
    io::IO,
    positions::Vector{Position};
    max_print=25,
    volume_digits=1,
    price_digits=2,
    data_renderer::Union{Function, Nothing}=nothing
)
    n = length(positions)
    if n == 0
        return
    end

    date_fmt = dateformat"yyyy-mm-dd HH:MM:SS"
    vol_fmt = x -> string(round(x, digits=volume_digits))
    price_fmt = x -> string(round(x, digits=price_digits))

    columns = [
        "Symbol"; "Volume"; "Open time"; "Open price";
        "Last quote"; "Last price"; "P&L";
        "Stop loss"; "Take profit"; "Close reason"
    ]
    if !isnothing(data_renderer)
        push!(columns, "Data")
    end

    idx_volume = findfirst(columns .== "Volume")
    idx_open_time = findfirst(columns .== "Open time")
    idx_open_price = findfirst(columns .== "Open price")
    idx_last_price = findfirst(columns .=="Last price")
    idx_last_quote = findfirst(columns .== "Last quote")
    idx_pnl = findfirst(columns .== "P&L")
    idx_stop_loss = findfirst(columns .== "Stop loss")
    idx_take_profit = findfirst(columns .== "Take profit")
    idx_data = findfirst(columns .== "Data")
    idx_close_reason = findfirst(columns .== "Close reason")

    formatter = (v, i, j) -> begin
        o = v
        if j == idx_volume
            o = vol_fmt(v)
        elseif j == idx_open_price || j == idx_last_price || j == idx_pnl || j == idx_stop_loss || j == idx_take_profit
            o = isnan(v) ? "—" : price_fmt(v)
        elseif j == idx_open_time || j == idx_last_quote
            o = Dates.format(v, date_fmt)
        elseif j == idx_data
            # position "data" field renderer
            o = data_renderer(positions[j], v)
        elseif j == idx_close_reason
            o = v == NullReason::CloseReason ? "—" : v
        end
        o
    end

    if !isnothing(idx_data)
        data = map(pos -> [pos.inst.symbol pos.size pos.open_dt pos.open_price pos.last_dt pos.last_price pos.pnl pos.stop_loss pos.take_profit pos.close_reason pos.data], positions)
    else
        data = map(pos -> [pos.inst.symbol pos.size pos.open_dt pos.open_price pos.last_dt pos.last_price pos.pnl pos.stop_loss pos.take_profit pos.close_reason], positions)
    end
    data = reduce(vcat, data)

    h_pos_green = Highlighter((data, i, j) -> j == idx_pnl && data[i, j] > 0, bold=true, foreground=:green)
    h_neg_red = Highlighter((data, i, j) -> j == idx_pnl && data[i, j] < 0, bold=true, foreground=:red)

    if !isnan(max_print) && size(data, 1) > max_print
        df = DataFrame(data, columns)
        pretty_table(io, first(df, max_print);
            highlighters = (h_pos_green, h_neg_red),
            formatters = formatter,
            compact_printing = false)
        println(io, " [...] $(n - max_print) more positions")
    else
        df = DataFrame(data, columns)
        pretty_table(io, df;
            highlighters = (h_pos_green, h_neg_red),
            formatters = formatter,
            compact_printing = false)
    end
end
