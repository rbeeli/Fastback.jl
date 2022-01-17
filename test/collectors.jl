@testset "Collectors" begin

    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]

    begin
        # periodic_collector
        f, collected = periodic_collector(Float64, Second(1))

        for i in 1:length(dts)
            f(dts[i], data[i])
        end

        @test length(collected.values) == 5
        @test all(map(x -> x[1], collected.values) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
        @test collected.last_dt == dts[end]
    end

    begin
        # predicate_collector
        predicate = (collected, dt, value) -> (dt - collected.last_dt) >= Second(1)
        f, collected = predicate_collector(Float64, predicate, 0.0)

        for i in 1:length(dts)
            f(dts[i], data[i])
        end

        @test length(collected.values) == 5
        @test all(map(x -> x[1], collected.values) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
        @test collected.last_dt == dts[end]
    end

    begin
        # min_value_collector
        f, collected = min_value_collector(Float64)

        for i in 1:length(dts)
            f(dts[i], data[i])
        end

        @test collected.min_value == minimum(data)
        @test collected.dt == dts[indexin(minimum(data), data)][1]
    end

    begin
        # max_value_collector
        f, collected = max_value_collector(Float64)

        for i in 1:length(dts)
            f(dts[i], data[i])
        end

        @test collected.max_value == maximum(data)
        @test collected.dt == dts[indexin(maximum(data), data)][1]
    end

    begin
        # drawdown_collector (P&L)
        p = (v, dt, equity) -> dt - v.last_dt >= Second(1)
        f, collected = drawdown_collector(PnL::DrawdownMode, p)

        for i in 1:length(dts)
            f(dts[i], data[i])
        end

        @test length(collected.values) == 5
        @test all(map(x -> x[1], collected.values) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
        @test collected.last_dt == dts[end]
        @test all(map(x -> x[2], collected.values) .== [0.0, -11, -5, -5, -10])
    end

    begin
        # drawdown_collector (%)
        p = (dv, dt, equity) -> dt - dv.last_dt >= Second(1)
        f, collected = drawdown_collector(Percentage::DrawdownMode, p)

        for i in 1:length(dts)
            f(dts[i], data[i])
        end

        @test length(collected.values) == 5
        @test all(map(x -> x[1], collected.values) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
        @test collected.last_dt == dts[end]
        @test all(map(x -> x[2], collected.values) .≈ [0.0, -11 / 110, -5 / 110, -5 / 110, -10 / 120])
    end

end
