## helper: third Friday of a month
function third_friday(year::Int, month::Int)
    d = Date(year, month, 1)
    while dayofweek(d) != Dates.Friday
        d += Day(1)
    end
    d + Week(2)
end

## helper: parse MES symbol to contract expiry (quarterly IMM)
function mes_expiry_from_symbol(sym::Symbol)
    m = match(r"^MES_([HMUZ])(\d{2})$", String(sym))
    m === nothing && throw(ArgumentError("Unsupported MES symbol format: $(sym)"))

    month_code = m.captures[1][1]
    yy = parse(Int, m.captures[2])
    month = month_code == 'H' ? 3 : (month_code == 'M' ? 6 : (month_code == 'U' ? 9 : 12))

    third_friday(2000 + yy, month)
end

## helper: build VOO total-return-like daily bid/ask/last from OHLCV + actions
function load_voo_total_return_df(ohlcv_path, dividends_path, splits_path; start_dt, end_dt, half_spread)
    ohlcv = DataFrame(CSV.File(ohlcv_path; dateformat="yyyy-mm-dd"))
    dividends = DataFrame(CSV.File(dividends_path; dateformat="yyyy-mm-dd"))
    splits = DataFrame(CSV.File(splits_path; dateformat="yyyy-mm-dd"))

    sort!(ohlcv, :date)
    ohlcv = ohlcv[(start_dt .<= Date.(ohlcv.date) .<= end_dt), :]

    div_by_dt = Dict{Date,Float64}()
    for row in eachrow(dividends)
        dt = Date(row.date)
        start_dt <= dt <= end_dt || continue
        div_by_dt[dt] = get(div_by_dt, dt, 0.0) + Float64(row.dividend)
    end

    split_ratio_by_dt = Dict{Date,Float64}()
    for row in eachrow(splits)
        dt = Date(row.date)
        start_dt <= dt <= end_dt || continue
        from = Float64(row.split_from)
        to = Float64(row.split_to)
        from == 0.0 && continue
        split_ratio_by_dt[dt] = get(split_ratio_by_dt, dt, 1.0) * (to / from)
    end

    n = nrow(ohlcv)
    n > 0 || throw(ArgumentError("No VOO rows loaded in requested date range."))

    tr_last = Vector{Float64}(undef, n)
    tr_last[1] = Float64(ohlcv.close[1])

    prev_close = Float64(ohlcv.close[1])
    @inbounds for i in 2:n
        dt = Date(ohlcv.date[i])
        close_now = Float64(ohlcv.close[i])
        div = get(div_by_dt, dt, 0.0)
        ratio = get(split_ratio_by_dt, dt, 1.0)

        tr_factor = (ratio * close_now + div) / prev_close
        tr_last[i] = tr_last[i - 1] * tr_factor
        prev_close = close_now
    end

    DataFrame(
        dt=Date.(ohlcv.date),
        bid=tr_last .- half_spread,
        ask=tr_last .+ half_spread,
        last=tr_last,
    )
end

## helper: build MES front-contract daily bid/ask/last from contract panel
function load_mes_front_df(path; start_dt, end_dt, half_spread)
    raw = DataFrame(CSV.File(path; dateformat="yyyy-mm-dd"))
    raw = raw[(start_dt .<= Date.(raw.date) .<= end_dt), :]

    front = combine(groupby(raw, :date)) do sdf
        idx = argmax(sdf.volume)
        (
            symbol=Symbol(sdf.symbol[idx]),
            last=Float64(sdf.close[idx]),
        )
    end

    rename!(front, :date => :dt)
    sort!(front, :dt)
    front.bid = front.last .- half_spread
    front.ask = front.last .+ half_spread

    front
end

## helper: build MES contract specs from front-symbol switch dates
function build_mes_contract_specs(front_df)
    symbols = Symbol.(front_df.symbol)
    dts = Date.(front_df.dt)

    specs = NamedTuple{(:symbol,:expiry,:roll_date),Tuple{Symbol,Date,Date}}[]
    active = symbols[1]

    for i in 2:length(symbols)
        sym = symbols[i]
        if sym != active
            push!(specs, (
                symbol=active,
                expiry=mes_expiry_from_symbol(active),
                roll_date=dts[i],
            ))
            active = sym
        end
    end

    push!(specs, (
        symbol=active,
        expiry=mes_expiry_from_symbol(active),
        roll_date=Date(0),
    ))

    specs
end

## helper: align two daily dataframes on common dates
function align_on_common_dates(voo_df, mes_df)
    common_dt = sort(collect(intersect(Set(voo_df.dt), Set(mes_df.dt))))
    common_set = Set(common_dt)

    voo_aligned = voo_df[in.(voo_df.dt, Ref(common_set)), :]
    mes_aligned = mes_df[in.(mes_df.dt, Ref(common_set)), :]

    sort!(voo_aligned, :dt)
    sort!(mes_aligned, :dt)

    voo_aligned, mes_aligned
end
