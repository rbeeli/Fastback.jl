using Dates
using TestItemRunner

@testitem "BinanceBroker defaults to DateTime schedules" begin
    using Test, Fastback, Dates

    @test BinanceBroker() isa BinanceBroker{DateTime}

    borrow_by_cash = Dict(:USD=>StepSchedule([(DateTime(2025, 1, 1), 0.10)]))
    broker = BinanceBroker(; borrow_by_cash=borrow_by_cash)
    @test broker isa BinanceBroker{DateTime}
    @test broker.borrow_by_cash == borrow_by_cash
    @test broker.lend_by_cash isa Dict{Symbol,StepSchedule{DateTime,Price}}
    @test isempty(broker.lend_by_cash)

    lend_by_cash = Dict(:USD=>StepSchedule([(DateTime(2025, 1, 1), 0.02)]))
    broker = BinanceBroker(; lend_by_cash=lend_by_cash)
    @test broker isa BinanceBroker{DateTime}
    @test broker.lend_by_cash == lend_by_cash
    @test broker.borrow_by_cash isa Dict{Symbol,StepSchedule{DateTime,Price}}
    @test isempty(broker.borrow_by_cash)
end

@testitem "BinanceBroker supports explicit time_type and rejects mismatched defaults" begin
    using Test, Fastback, Dates

    borrow_by_cash = Dict(:USD=>StepSchedule([(Date(2025, 1, 1), 0.10)]))
    broker = BinanceBroker(; time_type=Date, borrow_by_cash=borrow_by_cash)
    @test broker isa BinanceBroker{Date}
    @test broker.borrow_by_cash == borrow_by_cash

    @test_throws MethodError BinanceBroker(; borrow_by_cash=borrow_by_cash)
end
