using Dates
using TestItemRunner

@testitem "periodic_collector" begin
    using Test, Fastback, Dates
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]
    # periodic_collector
    f, collected = periodic_collector(Float64, Second(1))
    for i in eachindex(dts)
        should_collect(collected, dts[i]) && f(dts[i], data[i])
    end
    @test length(values(collected)) == 5
    @test all(dates(collected) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
    @test collected.last_dt == dts[end]
end

@testitem "predicate_collector" begin
    using Test, Fastback, Dates
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]
    # predicate_collector
    predicate = (collected, dt) -> (dt - collected.last_dt) >= Second(1)
    f, collected = predicate_collector(Float64, predicate, 0.0)
    for i in eachindex(dts)
        should_collect(collected, dts[i]) && f(dts[i], data[i])
    end
    @test length(dates(collected)) == 5
    @test all(dates(collected) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
    @test collected.last_dt == dts[end]
end

@testitem "min_value_collector" begin
    using Test, Fastback, Dates
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]
    # min_value_collector
    f, collected = min_value_collector(Float64)
    for i in eachindex(dts)
        should_collect(collected, data[i]) && f(dts[i], data[i])
    end
    @test collected.min_value == minimum(data)
    @test collected.dt == dts[indexin(minimum(data), data)][1]
end

@testitem "max_value_collector" begin
    using Test, Fastback, Dates
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]
    # max_value_collector
    f, collected = max_value_collector(Float64)
    for i in eachindex(dts)
        should_collect(collected, data[i]) && f(dts[i], data[i])
    end
    @test collected.max_value == maximum(data)
    @test collected.dt == dts[indexin(maximum(data), data)][1]
end

@testitem "drawdown_collector_pnl" begin
    using Test, Fastback, Dates
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]
    # drawdown_collector (P&L)
    f, collected = drawdown_collector(DrawdownMode.PnL, Second(1))
    for i in eachindex(dts)
        should_collect(collected, dts[i]) && f(dts[i], data[i])
    end
    @test length(dates(collected)) == 5
    @test length(values(collected)) == 5
    @test all(dates(collected) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
    @test collected.last_dt == dts[end]
    println(values(collected))
    @test all(values(collected) .== [0.0, -11, -5, -5, -10])
end

@testitem "drawdown_collector_pct" begin
    using Test, Fastback, Dates
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]
    # drawdown_collector (%)
    f, collected = drawdown_collector(DrawdownMode.Percentage, Second(1))
    for i in eachindex(dts)
        should_collect(collected, dts[i]) && f(dts[i], data[i])
    end
    @test length(dates(collected)) == 5
    @test length(values(collected)) == 5
    @test all(dates(collected) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
    @test collected.last_dt == dts[end]
    @test all(values(collected) .≈ [0.0, -11 / 110, -5 / 110, -5 / 110, -10 / 120])
end

@testitem "periodic_collector with Date" begin
    using Test, Fastback, Dates, Tables

    start_date = Date(2020, 1, 1)
    collect_equity, equity_data = periodic_collector(Float64, Day(1); time_type=Date)

    for offset in 0:2
        dt = start_date + Day(offset)
        should_collect(equity_data, dt) && collect_equity(dt, 100.0 + offset)
    end

    @test equity_data.last_dt == start_date + Day(2)
    schema = Tables.schema(equity_data)
    @test schema.types[1] == Date
    rows = collect(Tables.rows(equity_data))
    @test rows[1].date isa Date
    @test rows[end].date == start_date + Day(2)
end
