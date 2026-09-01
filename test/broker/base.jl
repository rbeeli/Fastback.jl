using Dates
using TestItemRunner

@testitem "CommissionQuote validates finite inputs" begin
    using Test, Fastback

    q = CommissionQuote(; fixed=1.0, pct=0.001)
    @test q.fixed == 1.0
    @test q.pct == 0.001

    @test_throws ArgumentError CommissionQuote(; fixed=NaN, pct=0.0)
    @test_throws ArgumentError CommissionQuote(; fixed=0.0, pct=NaN)
end

@testitem "StepSchedule returns piecewise-constant values" begin
    using Test, Fastback, Dates

    sched = StepSchedule([
        (DateTime(2025, 1, 1), 0.01),
        (DateTime(2025, 2, 1), 0.02),
        (DateTime(2025, 3, 1), 0.03),
    ])

    @test value_at(sched, DateTime(2024, 12, 1)) == 0.01
    @test value_at(sched, DateTime(2025, 1, 20)) == 0.01
    @test value_at(sched, DateTime(2025, 2, 1)) == 0.02
    @test value_at(sched, DateTime(2025, 3, 15)) == 0.03
end

@testitem "StepSchedule normalizes ordering and rejects ambiguous schedules" begin
    using Test, Fastback, Dates

    march = DateTime(2025, 3, 1)
    january = DateTime(2025, 1, 1)
    february = DateTime(2025, 2, 1)
    starts = [march, january, february]
    values = [0.03, 0.01, 0.02]
    sched = StepSchedule(starts, values)

    @test sched.starts == [january, february, march]
    @test sched.values == [0.01, 0.02, 0.03]
    @test starts == [march, january, february]
    @test values == [0.03, 0.01, 0.02]
    @test value_at(sched, DateTime(2025, 2, 15)) == 0.02

    @test_throws ArgumentError StepSchedule(DateTime[], Float64[])
    @test_throws ArgumentError StepSchedule(
        [january, january],
        [0.01, 0.02],
    )
    @test_throws ArgumentError StepSchedule([january], Float64[])
end
