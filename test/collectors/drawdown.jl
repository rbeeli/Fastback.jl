using Dates
using TestItemRunner

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
    @test all(values(collected) .== [0.0, -11, -5, -5, -10])
end

@testitem "drawdown_collector_pct" begin
    using Test, Fastback, Dates, Tables

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
    @test Tables.schema(collected).names == (:date, :drawdown)
    @test all(values(collected) .≈ [0.0, -11 / 110, -5 / 110, -5 / 110, -10 / 120])
end
