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

    benchmark_by_cash_date = Dict(:USD=>StepSchedule([(Date(2025, 1, 1), 0.03)]))
    broker_date = IBKRProFixedBroker(; time_type=Date, benchmark_by_cash=benchmark_by_cash_date)
    @test broker_date isa IBKRProFixedBroker{Date}
    @test broker_date.benchmark_by_cash == benchmark_by_cash_date

    @test_throws MethodError IBKRProFixedBroker(; benchmark_by_cash=benchmark_by_cash_date)
end
