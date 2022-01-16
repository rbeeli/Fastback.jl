using PrettyTables


# --------------- Instrument ---------------

function Base.show(io::IO, inst::Instrument)
    data_str = isnothing(inst.data) ? "" : "  data=<object>"
    print(io, "[Instrument] symbol=$(inst.symbol)$data_str")
end


# --------------- BidAsk ---------------

function Base.show(io::IO, ba::BidAsk)
    print(io, "[BidAsk] dt=$(ba.dt)  bid=$(ba.bid)  ask=$(ba.ask)")
end


# --------------- Position ---------------

function Base.show(io::IO, pos::Position)
    size_str = @sprintf("%.2f", pos.size)
    if sign(pos.size) != -1
        size_str = " " * size_str
    end
    pnl_str = @sprintf("%+.2f", pos.pnl)
    data_str = isnothing(pos.data) ? "nothing" : "<object>"
    print(io, "[Position] $(pos.inst.symbol) $(pos.dir) $size_str  "*
        "open=($(Dates.format(pos.open_dt, "yyyy-mm-dd HH:MM:SS")), $(@sprintf("%.2f", pos.open_price)))  "*
        "last=($(Dates.format(pos.last_dt, "yyyy-mm-dd HH:MM:SS")), $(@sprintf("%.2f", pos.last_price)))  "*
        "pnl=$pnl_str  stop_loss=$(@sprintf("%.2f", pos.stop_loss))  take_profit=$(@sprintf("%.2f", pos.take_profit))  "*
        "close_reason=$(pos.close_reason)  data=$data_str")
end

function print_positions(positions::Vector{Position};
    max_print=25, volume_digits=1, price_digits=2,
    data_renderer::Union{Function, Nothing}=nothing, kwargs...
)
    print_positions(stdout, positions::Vector{Position}; max_print, volume_digits, price_digits, data_renderer, kwargs...)
end

function print_positions(io::IO, positions::Vector{Position};
    max_print=25, volume_digits=1, price_digits=2,
    data_renderer::Union{Function, Nothing}=nothing
)
    n = length(positions)
    if n == 0
        return
    end

    df = dateformat"yyyy-mm-dd HH:MM:SS"
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
            o = Dates.format(v, df)
        elseif j == idx_data
            # position "data" field renderer
            o = data_renderer(positions[j], v)
        elseif j == idx_close_reason
            o = v == Unspecified::CloseReason ? "—" : v
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
        pretty_table(io, data[1:max_print, :], columns;
            highlighters = (h_pos_green, h_neg_red),
            formatters = formatter,
            compact_printing = false)
        println(io, " [...] $(n - max_print) more positions")
    else
        pretty_table(io, data, columns;
            highlighters = (h_pos_green, h_neg_red),
            formatters = formatter,
            compact_printing = false)
    end
end


# --------------- OpenOrder ---------------

function Base.show(io::IO, order::OpenOrder)
    print(io, "[OpenOrder] $(order.inst.symbol) $(order.size) $(order.dir)  stop_loss=$(@sprintf("%.2f", order.stop_loss))  take_profit=$(@sprintf("%.2f", order.take_profit))")
end


# --------------- CloseOrder ---------------

function Base.show(io::IO, order::CloseOrder)
    print(io, "[CloseOrder] $(order.pos)  $(order.close_reason)")
end


# --------------- CloseAllOrder ---------------

function Base.show(io::IO, order::CloseAllOrder)
    print(io, "[CloseAllOrder]")
end


# --------------- Account ---------------

function Base.show(io::IO, acc::Account; volume_digits=1, price_digits=2, kwargs...)
    # volume_digits and price_digits are passed to print_positions(...)
    x, y = displaysize(io)
    
    get_color(val) = val >= 0 ? (val == 0 ? :black : :green) : :red

    title = " ACCOUNT SUMMARY "
    title_line = '━'^(floor(Int64, (y - length(title))/2))
    println(io, "")
    println(io, title_line * title * title_line)
    println(io, " ", "Initial balance:    $(@sprintf("%.2f", acc.initial_balance))")
    print(io,   " ", "Balance:            $(@sprintf("%.2f", acc.balance))")
    print(io, " (")
    printstyled(io, "$(@sprintf("%+.2f", balance_ret(acc)*100))%"; color=get_color(balance_ret(acc)))
    print(io, ")\n")
    print(io, " ", "Equity:             $(@sprintf("%.2f", acc.equity))")
    print(io, " (")
    printstyled(io, "$(@sprintf("%+.2f", equity_ret(acc)*100))%"; color=get_color(equity_ret(acc)))
    print(io, ")\n")
    println(io, "")
    println(io, " ", "Open positions:     $(length(acc.open_positions))")
    print_positions(io, acc.open_positions; kwargs...)
    println(io, "")
    println(io, " ", "Closed positions:   $(length(acc.closed_positions))")
    print_positions(io, acc.closed_positions; kwargs...)
    println(io, '━'^y)
    println(io, "")
end
