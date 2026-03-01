"""
Build VOO total-return-like daily bid/ask/last from OHLCV and actions.
"""
function load_voo_total_return_df(ohlcv_path, dividends_path, splits_path; start_dt, end_dt, half_spread)
    ohlcv = DataFrame(CSV.File(ohlcv_path; dateformat="yyyy-mm-dd"))
    dividends = DataFrame(CSV.File(dividends_path; dateformat="yyyy-mm-dd"))
    splits = DataFrame(CSV.File(splits_path; dateformat="yyyy-mm-dd"))

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

"""
Build MES front-contract daily bid/ask/last from the contract panel.
"""
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

"""
Build MES contract specs from an explicit roll schedule CSV.
"""
function build_mes_contract_specs(path; start_dt, end_dt)
    raw = DataFrame(CSV.File(path; dateformat="yyyy-mm-dd"))
    sort!(raw, :roll_date)

    roll_dts = Date.(raw.roll_date)
    from_symbols = Symbol.(raw.from_contract)
    to_symbols = Symbol.(raw.to_contract)
    from_expiries = Date.(raw.from_expiration)
    to_expiries = Date.(raw.to_expiration)

    specs = NamedTuple{(:symbol,:expiry,:roll_date),Tuple{Symbol,Date,Date}}[]

    start_idx = findfirst(roll_dts .>= start_dt)
    if start_idx === nothing
        terminal_symbol = to_symbols[end]
        terminal_expiry = to_expiries[end]
        push!(specs, (symbol=terminal_symbol, expiry=terminal_expiry, roll_date=Date(0)))
        return specs
    end

    i = start_idx
    while i <= length(roll_dts) && roll_dts[i] <= end_dt
        push!(specs, (
            symbol=from_symbols[i],
            expiry=from_expiries[i],
            roll_date=roll_dts[i],
        ))
        i += 1
    end

    terminal_symbol = i <= length(roll_dts) ? from_symbols[i] : to_symbols[end]
    terminal_expiry = i <= length(roll_dts) ? from_expiries[i] : to_expiries[end]
    push!(specs, (symbol=terminal_symbol, expiry=terminal_expiry, roll_date=Date(0)))

    specs
end

"""
Load example 9 VOO daily series from the local data folder.
"""
function load_voo_df(data_dir; start_dt, end_dt, half_spread)
    ohlcv_path = joinpath(data_dir, "VOO_ohlcv_daily.csv")
    dividends_path = joinpath(data_dir, "VOO_dividends.csv")
    splits_path = joinpath(data_dir, "VOO_splits.csv")
    load_voo_total_return_df(
        ohlcv_path,
        dividends_path,
        splits_path;
        start_dt=start_dt,
        end_dt=end_dt,
        half_spread=half_spread,
    )
end

"""
Load example 9 MES front-contract daily series from the local data folder.
"""
function load_mes_front_data_df(data_dir; start_dt, end_dt, half_spread)
    contracts_path = joinpath(data_dir, "MES_contracts.csv")
    load_mes_front_df(
        contracts_path;
        start_dt=start_dt,
        end_dt=end_dt,
        half_spread=half_spread,
    )
end

"""
Load example 9 MES roll specs from the local data folder.
"""
function load_mes_contract_specs(data_dir; start_dt, end_dt)
    roll_dates_path = joinpath(data_dir, "MES_roll_dates.csv")
    build_mes_contract_specs(roll_dates_path; start_dt=start_dt, end_dt=end_dt)
end

"""
Load example 9 USD benchmark schedule from the local data folder.
"""
function load_usd_benchmark_schedule(data_dir)
    path = joinpath(data_dir, "IBKR_USD_benchmark.csv")
    StepSchedule([
        (Date(row.start_dt), Float64(row.usd_benchmark))
        for row in CSV.File(path; dateformat="yyyy-mm-dd")
    ])
end

"""
Align two daily dataframes on shared dates.
"""
function align_on_common_dates(voo_df, mes_df)
    common_dt = sort(collect(intersect(Set(voo_df.dt), Set(mes_df.dt))))
    common_set = Set(common_dt)

    voo_aligned = voo_df[in.(voo_df.dt, Ref(common_set)), :]
    mes_aligned = mes_df[in.(mes_df.dt, Ref(common_set)), :]

    sort!(voo_aligned, :dt)
    sort!(mes_aligned, :dt)

    voo_aligned, mes_aligned
end
