@testset "Position functions" begin
    inst = Instrument("TEST")
    dt1 = DateTime(2000, 1, 1)
    ba1 = BidAsk(dt1, 500.0, 501.1)

    dt2 = DateTime(2000, 1, 2)
    ba2 = BidAsk(dt2, 505.0, 506.5)

    begin
        # long
        pos = Position(inst, 500.0, Long, ba1, dt1, ba1.ask, ba2, dt2, ba2.bid, 0.0, 0.0, NullReason::CloseReason, 0.0, nothing)

        @test is_long(pos)
        @test !is_short(pos)

        @test pos.open_price == 501.1
        @test open_price(pos.dir, ba1) == 501.1
        @test pos.last_price == 505.0
        @test close_price(pos.dir, ba2) == 505.0

        @test pnl_net(pos) == 500.0 * (pos.last_price - pos.open_price)
        @test pnl_gross(pos) == 500.0 * (midprice(pos.last_quote) - midprice(pos.open_quote))

        @test return_net(pos) == (pos.last_price - pos.open_price) / pos.open_price
        @test return_gross(pos) == (midprice(pos.last_quote) - midprice(pos.open_quote)) / midprice(pos.open_quote)
    end

    begin
        # short
        pos = Position(inst, -500.0, Short, ba1, dt1, ba1.bid, ba2, dt2, ba2.ask, 0.0, 0.0, NullReason::CloseReason, 0.0, nothing)

        @test !is_long(pos)
        @test is_short(pos)

        @test pos.open_price == 500.0
        @test open_price(pos.dir, ba1) == 500.0
        @test pos.last_price == 506.5
        @test close_price(pos.dir, ba2) == 506.5

        @test pnl_net(pos) == -500.0 * (pos.last_price - pos.open_price)
        @test pnl_gross(pos) == -500.0 * (midprice(pos.last_quote) - midprice(pos.open_quote))

        @test return_net(pos) == -(pos.last_price - pos.open_price) / pos.open_price
        @test return_gross(pos) == -(midprice(pos.last_quote) - midprice(pos.open_quote)) / midprice(pos.open_quote)
    end
end
