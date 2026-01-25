using Dates
using TestItemRunner

@testitem "Position long pnl/return" begin
    using Test, Fastback, Dates
    acc = Account(; base_currency=:USD);
    deposit!(acc, Cash(:USD), 100_000.0)
    TEST = register_instrument!(acc, Instrument(Symbol("TEST/USD"), :TEST, :USD))
    px1, px2 = 500.0, 505.0
    # long
    pos = Position{DateTime}(1, TEST; avg_entry_price=px1, avg_settle_price=px1, quantity=500.0)
    @test is_long(pos)
    @test !is_short(pos)
    @test calc_pnl_local(pos, px2) == pos.quantity * (px2 - pos.avg_settle_price)
    @test calc_return_local(pos, px2) ≈ (px2 - px1) / px1
end

@testitem "Position short pnl/return" begin
    using Test, Fastback, Dates
    acc = Account(; base_currency=:USD);
    deposit!(acc, Cash(:USD), 100_000.0)
    TEST = register_instrument!(acc, Instrument(Symbol("TEST/USD"), :TEST, :USD))
    px1, px2 = 500.0, 505.0
    # short
    pos = Position{DateTime}(2, TEST; avg_entry_price=px1, avg_settle_price=px1, quantity=-500.0)
    @test !is_long(pos)
    @test is_short(pos)
    @test calc_pnl_local(pos, px2) == pos.quantity * (px2 - pos.avg_settle_price)
    @test calc_return_local(pos, px2) ≈ -(px2 - px1) / px1
end

@testitem "calc_realized_qty" begin
    using Test, Fastback
    # Test 1: long position, sell order more than position
    @test calc_realized_qty(10, -30) == 10
    # Test 2: long position, sell order less than position
    @test calc_realized_qty(10, -5) == 5
    # Test 3: short position, buy order more than position
    @test calc_realized_qty(-10, 30) == -10
    # Test 4: short position, buy order less than position
    @test calc_realized_qty(-10, 5) == -5
    # Test 4: short position, buy order same as position
    @test calc_realized_qty(-10, 10) == -10
    # Test 5: long position, buy order
    @test calc_realized_qty(10, 5) == 0
    # Test 6: short position, sell order
    @test calc_realized_qty(-10, -5) == 0
    # Test 7: no position, sell order
    @test calc_realized_qty(0, -5) == 0
    # Test 8: no position, buy order
    @test calc_realized_qty(0, 5) == 0
    # Test 9: no op
    @test calc_realized_qty(0, 0) == 0
end

@testitem "calc_exposure_increase_quantity" begin
    using Test, Fastback
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

@testitem "mark_price set on fills and marks" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)
    inst = register_instrument!(acc, Instrument(
        Symbol("MK/USD"),
        :MK,
        :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.0,
        margin_init_short=0.0,
        margin_maint_long=0.0,
        margin_maint_short=0.0,
    ))

    # Fill long; mark should be fill price
    order = Order(oid!(acc), inst, DateTime(2026, 1, 1), 100.0, 1.0)
    trade = fill_order!(acc, order, order.date, order.price)
    pos = get_position(acc, inst)
    @test pos.mark_price == 100.0

    # Update with bid/ask; long uses bid as close
    update_marks!(acc, inst; dt=order.date, bid=101.0, ask=102.0)
    @test pos.mark_price == 101.0

    # Flip to short; mark on fill should update
    order2 = Order(oid!(acc), inst, DateTime(2026, 1, 2), 103.0, -2.0)
    fill_order!(acc, order2, order2.date, order2.price)
    @test pos.mark_price == 103.0

    # For short, close price comes from ask
    update_marks!(acc, inst; dt=order2.date, bid=98.0, ask=99.0)
    @test pos.mark_price == 99.0
end
