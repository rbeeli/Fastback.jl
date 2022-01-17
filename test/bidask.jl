@testset "BidAsk functions" begin
    dt = DateTime(2000, 1, 1)
    ba = BidAsk(dt, 500.0, 501.1)

    @test midprice(ba) == (500.0 + 501.1) / 2
    @test midprice(500.0, 501.1) == (500.0 + 501.1) / 2

    @test spread(ba) == 501.1 - 500.0
    @test spread(500.0, 501.1) == 501.1 - 500.0
end
