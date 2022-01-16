@testset "Parameters combinations" begin
    begin
        # all combinations
        universe = Dict{Any, Vector{Any}}(:wnd => [1,2,3], :mode => ["A", "B"], :coef => [0.1, 0.5, 1.0])
        combinations = params_combinations(universe)

        # check correct number of combinations
        @test length(combinations) == prod(map(length, values(universe)))

        # check all combinations have exactly three parameters
        @test all(map(x -> length(x) == 3, combinations))
    end

    begin
        # filtered combinations for which hold: wnd > 1 if mode == 'A'
        universe = Dict{Any, Vector{Any}}(:wnd => [1,2,3], :mode => ["A", "B"], :coef => [0.1, 0.5, 1.0])
        f = x -> x[:mode] != "A" || x[:wnd] > 1
        combinations = params_combinations(universe; filter=f)

        # check correct number of combinations
        @test length(combinations) == 15

        # check all combinations have exactly three parameters
        @test all(map(x -> length(x) == 3, combinations))
    end

    begin
        # filter all (empty result)
        universe = Dict{Any, Vector{Any}}("wnd" => [1,2,3], "mode" => ["A", "B"], "coef" => [0.1, 0.5, 1.0])
        combinations = params_combinations(universe; filter=x -> false)

        # check correct number of combinations
        @test length(combinations) == 0
    end

    begin
        # shuffle
        universe = Dict{Any, Vector{Any}}(:a => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], :b => ["a", "b", "c"])
        combinations1 = params_combinations(universe; shuffle=true)
        combinations21 = params_combinations(universe; shuffle=false)
        combinations22 = params_combinations(universe; shuffle=false)

        @test !all(combinations1 .== combinations21)
        @test all(combinations21 .== combinations22)
    end
end
