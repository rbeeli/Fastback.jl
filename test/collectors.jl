using Fastback
using Test
using Dates

@testset "periodic_collector" begin
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]

    begin
        # periodic_collector
        f, collected = periodic_collector(Float64, Second(1))

        for i in eachindex(dts)
            should_collect(collected, dts[i]) && f(dts[i], data[i])
        end

        @test length(values(collected)) == 5
        @test all(dates(collected) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
        @test collected.last_dt == dts[end]
    end
end


@testset "predicate_collector" begin
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]

    begin
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
end


@testset "min/max_value_collector" begin
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]

    begin
        # min_value_collector
        f, collected = min_value_collector(Float64)

        for i in eachindex(dts)
            f(dts[i], data[i])
        end

        @test collected.min_value == minimum(data)
        @test collected.dt == dts[indexin(minimum(data), data)][1]
    end

    begin
        # max_value_collector
        f, collected = max_value_collector(Float64)

        for i in eachindex(dts)
            f(dts[i], data[i])
        end

        @test collected.max_value == maximum(data)
        @test collected.dt == dts[indexin(maximum(data), data)][1]
    end
end

@testset "drawdown_collector" begin
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]
    
    begin
        # drawdown_collector (P&L)
        p = (v, dt, equity) -> dt - v.last_dt >= Second(1)
        f, collected = drawdown_collector(DrawdownMode.PnL, p)

        for i in eachindex(dts)
            f(dts[i], data[i])
        end

        @test length(dates(collected)) == 5
        @test length(values(collected)) == 5
        @test all(dates(collected) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
        @test collected.last_dt == dts[end]
        @test all(values(collected) .== [0.0, -11, -5, -5, -10])
    end

    begin
        # drawdown_collector (%)
        p = (dv, dt, equity) -> dt - dv.last_dt >= Second(1)
        f, collected = drawdown_collector(DrawdownMode.Percentage, p)

        for i in eachindex(dts)
            f(dts[i], data[i])
        end

        @test length(dates(collected)) == 5
        @test length(values(collected)) == 5
        @test all(dates(collected) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
        @test collected.last_dt == dts[end]
        @test all(values(collected) .≈ [0.0, -11 / 110, -5 / 110, -5 / 110, -10 / 120])
    end
end
