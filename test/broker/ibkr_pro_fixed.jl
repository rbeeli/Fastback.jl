using Dates
using TestItemRunner

@testitem "IBKRProFixedBroker defaults to DateTime schedules" begin
    using Test, Fastback, Dates

    @test IBKRProFixedBroker() isa IBKRProFixedBroker{DateTime}

    benchmark_by_cash = Dict(:USD=>StepSchedule([(DateTime(2025, 1, 1), 0.03)]))
    broker = IBKRProFixedBroker(; benchmark_by_cash=benchmark_by_cash)
    @test broker isa IBKRProFixedBroker{DateTime}
    @test broker.benchmark_by_cash == benchmark_by_cash
    @test broker.benchmark_by_cash isa Dict{Symbol,StepSchedule{DateTime,Price}}
    @test broker.short_proceeds_exclusion == 1.0
    @test broker.short_proceeds_rebate_spread == broker.lend_spread

    benchmark_by_cash_date = Dict(:USD=>StepSchedule([(Date(2025, 1, 1), 0.03)]))
    broker_date = IBKRProFixedBroker(; time_type=Date, benchmark_by_cash=benchmark_by_cash_date)
    @test broker_date isa IBKRProFixedBroker{Date}
    @test broker_date.benchmark_by_cash == benchmark_by_cash_date

    @test_throws MethodError IBKRProFixedBroker(; benchmark_by_cash=benchmark_by_cash_date)
end

@testitem "IBKRProFixedBroker short proceeds uses benchmark rebate spread" begin
    using Test, Fastback, Dates

    benchmark_by_cash = Dict(:USD=>StepSchedule([(DateTime(2025, 1, 1), 0.03)]))
    broker = IBKRProFixedBroker(;
        benchmark_by_cash=benchmark_by_cash,
        short_proceeds_exclusion=1.0,
        short_proceeds_rebate_spread=0.01,
    )
    dt = DateTime(2025, 1, 10)
    usd = Cash(1, :USD, 2)
    eur = Cash(2, :EUR, 2)
    exclude_frac, rebate_rate = broker_short_proceeds_rates(broker, usd, dt)

    @test exclude_frac == 1.0
    @test rebate_rate ≈ 0.02 atol=1e-12

    ex_unknown, rebate_unknown = broker_short_proceeds_rates(broker, eur, dt)
    @test ex_unknown == 1.0
    @test rebate_unknown == 0.0
end
