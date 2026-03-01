using Dates
using TestItemRunner

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
