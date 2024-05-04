using Fastback
using Test
using Dates

@testset "Position calc_pnl calc_return" begin
    acc = Account{Nothing,Nothing}(Asset(1, :USD))
    add_funds!(acc, acc.base_asset, 100_000.0)

    TEST = register_instrument!(acc, Instrument(1, Symbol("TEST/USD"), :TEST, :USD))

    dt1, px1 = DateTime(2000, 1, 1), 500.0
    dt2, px2 = DateTime(2000, 1, 2), 505.0

    begin
        # long
        pos = Position{Nothing}(1, TEST; avg_price=px1, quantity=500.0)

        @test is_long(pos)
        @test !is_short(pos)
        @test pos.avg_price == px1
        @test pos.quantity == 500.0

        @test calc_pnl(pos, px2) == pos.quantity * (px2 - pos.avg_price)
        @test calc_return(pos, px2) ≈ (px2 - px1) / px1
    end

    begin
        # short
        pos = Position{Nothing}(2, TEST; avg_price=px1, quantity=-500.0)

        @test !is_long(pos)
        @test is_short(pos)
        @test pos.avg_price == px1
        @test pos.quantity == -500.0

        @test calc_pnl(pos, px2) == pos.quantity * (px2 - pos.avg_price)
        @test calc_return(pos, px2) ≈ -(px2 - px1) / px1
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
