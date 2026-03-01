using Dates
using TestItemRunner

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
