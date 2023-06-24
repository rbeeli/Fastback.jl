@testset "Parameters combinations" begin
    begin
        # all combinations
        universe = Dict{Any,Vector{Any}}(:wnd => [1, 2, 3], :mode => ["A", "B"], :coef => [0.1, 0.5, 1.0])
        combinations = params_combinations(universe)

        # check correct number of combinations
        @test length(combinations) == prod(map(length, values(universe)))

        # check all combinations have exactly three parameters
        @test all(map(x -> length(x) == 3, combinations))
    end

    begin
        # filtered combinations for which hold: wnd > 1 if mode == 'A'
        universe = Dict{Any,Vector{Any}}(:wnd => [1, 2, 3], :mode => ["A", "B"], :coef => [0.1, 0.5, 1.0])
        f = x -> x[:mode] != "A" || x[:wnd] > 1
        combinations = params_combinations(universe; filter=f)

        # check correct number of combinations
        @test length(combinations) == 15

        # check all combinations have exactly three parameters
        @test all(map(x -> length(x) == 3, combinations))
    end

    begin
        # filter all (empty result)
        universe = Dict{Any,Vector{Any}}("wnd" => [1, 2, 3], "mode" => ["A", "B"], "coef" => [0.1, 0.5, 1.0])
        combinations = params_combinations(universe; filter=x -> false)

        # check correct number of combinations
        @test length(combinations) == 0
    end

    begin
        # shuffle
        universe = Dict{Any,Vector{Any}}(:a => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], :b => ["a", "b", "c"])
        combinations1 = params_combinations(universe; shuffle=true)
        combinations21 = params_combinations(universe; shuffle=false)
        combinations22 = params_combinations(universe; shuffle=false)

        @test !all(combinations1 .== combinations21)
        @test all(combinations21 .== combinations22)
    end
end

@testset "estimate_eta / format_period_HHMMSS" begin
    @testset "estimate_eta" begin
        @test estimate_eta(Dates.Hour(1), 0.5) == convert(Millisecond, Hour(1))
        @test estimate_eta(Dates.Second(30), 0.1) == convert(Millisecond, Second(270))
        @test isnan(estimate_eta(Dates.Minute(20), 0))
    end

    @testset "format_period_HHMMSS" begin
        @test format_period_HHMMSS(Dates.Hour(1) + Dates.Minute(30) + Dates.Second(45)) == "01:30:45"
        @test format_period_HHMMSS(NaN) == "Inf"
        @test format_period_HHMMSS(NaN, nan_value="N/A") == "N/A"
    end
end