@testset "Position calc_pnl calc_return" begin
    inst = Instrument(1, "TEST")
    
    ba1 = BidAsk(DateTime(2000, 1, 1), 500.0, 501.1)
    ba2 = BidAsk(DateTime(2000, 1, 2), 505.0, 506.5)

    begin
        # long
        pos = Position(inst.index, inst, 500.0, Vector{Order}(), ba1.ask, 0.0)

        @test is_long(pos)
        @test !is_short(pos)
        @test pos.avg_price == ba1.ask
        @test pos.quantity == 500.0

        book = OrderBook(1, inst, ba2)

        @test calc_pnl(pos, book) == pos.quantity * (fill_price(-pos.quantity, book) - pos.avg_price)
        @test calc_return(pos, book) == (ba2.bid - ba1.ask)/ba1.ask
    end

    begin
        # short
        pos = Position(inst.index, inst, -500.0, Vector{Order}(), ba1.bid, 0.0)

        @test !is_long(pos)
        @test is_short(pos)
        @test pos.avg_price == ba1.bid
        @test pos.quantity == -500.0

        book = OrderBook(1, inst, ba2)

        @test calc_pnl(pos, book) == pos.quantity * (fill_price(-pos.quantity, book) - pos.avg_price)
        @test calc_return(pos, book) == (ba1.bid - ba2.ask)/ba1.bid
    end
end


@testset "Position calc_realized_quantity" begin
    # Test 1: long position, sell order more than position
    @test calc_realized_quantity(10, -30) == 10

    # Test 2: long position, sell order less than position
    @test calc_realized_quantity(10, -5) == 5

    # Test 3: short position, buy order more than position
    @test calc_realized_quantity(-10, 30) == -10

    # Test 4: short position, buy order less than position
    @test calc_realized_quantity(-10, 5) == -5

    # Test 4: short position, buy order same as position
    @test calc_realized_quantity(-10, 10) == -10

    # Test 5: long position, buy order
    @test calc_realized_quantity(10, 5) == 0

    # Test 6: short position, sell order
    @test calc_realized_quantity(-10, -5) == 0

    # Test 7: no position, sell order
    @test calc_realized_quantity(0, -5) == 0

    # Test 8: no position, buy order
    @test calc_realized_quantity(0, 5) == 0

    # Test 9: no op
    @test calc_realized_quantity(0, 0) == 0
end


@testset "Position calc_exposure_increase_quantity" begin
    # Test 1: long position, buy order more than position
    @test calc_exposure_increase_quantity(10, 20) == 20

    # Test 2: long position, buy order less than position
    @test calc_exposure_increase_quantity(10, 5) == 5

    # Test 3: short position, sell order more than position
    @test calc_exposure_increase_quantity(-10, -20) == -20

    # Test 4: short position, sell order less than position
    @test calc_exposure_increase_quantity(-10, -5) == -5

    # Test 5: long position, sell order
    @test calc_exposure_increase_quantity(10, -5) == 0

    # Test 6: short position, buy order
    @test calc_exposure_increase_quantity(-10, 5) == 0

    # Test 7: no position, sell order
    @test calc_exposure_increase_quantity(0, -5) == -5

    # Test 8: no position, buy order
    @test calc_exposure_increase_quantity(0, 5) == 5

    # Test 9: no op
    @test calc_exposure_increase_quantity(0, 0) == 0
end
