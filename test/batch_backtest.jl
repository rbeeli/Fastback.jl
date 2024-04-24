using Fastback
using Test
using Dates

@testset "batch_backtest" begin
    params = params_combinations(
        Dict(
            :a => 1:5,
            :b => ["A", "B", "C"]
        )
    )

    function backtest_func(; a, b)
        @assert typeof(a) == Int
        @assert typeof(b) == String
        true
    end

    res = batch_backtest(Bool, params, backtest_func)

    @test length(res) == length(params)
end

@testset "finished_func" begin
    params = params_combinations(
        Dict(
            :a => 1:5,
            :b => ["A", "B", "C"]
        )
    )

    function backtest_func(; a, b)
        @assert typeof(a) == Int
        @assert typeof(b) == String
        true
    end

    finished_called = false
    function finished_func(params, acc)
        finished_called = true
    end

    res = batch_backtest(Bool, params, backtest_func; finished_func=finished_func)

    @test finished_called
    @test length(res) == length(params)
end
