using Fastback


@testset "batch_backtest" begin

    params = params_combinations(Dict{Any,Vector{Any}}(
        :a => 1:5,
        :b => ["A", "B", "C"]))

    function backtest_func(; a, b)
        acc = Account(10_000.0)
        acc
    end

    accs = batch_backtest(Account, params, backtest_func)

    @test length(accs) == length(params)
end

@testset "finished_func" begin

    params = params_combinations(Dict{Any,Vector{Any}}(
        :a => 1:5,
        :b => ["A", "B", "C"]))

    function backtest_func(; a, b)
        acc = Account(10_000.0)
        acc
    end

    finished_called = false
    function finished_func(params, acc)
        finished_called = true
    end

    accs = batch_backtest(Account, params, backtest_func; finished_func = finished_func)

    @test finished_called
    @test length(accs) == length(params)
end
