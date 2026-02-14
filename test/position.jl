using Dates
using TestItemRunner

@testitem "Position long pnl/return" begin
    using Test, Fastback, Dates
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoBrokerProfile(), base_currency=base_currency);
    deposit!(acc, :USD, 100_000.0)
    TEST = register_instrument!(acc, spot_instrument(Symbol("TEST/USD"), :TEST, :USD))
    px1, px2 = 500.0, 505.0
    # long
    pos = Position{DateTime}(1, TEST; avg_entry_price=px1, avg_settle_price=px1, quantity=500.0)
    @test is_long(pos)
    @test !is_short(pos)
    @test Fastback.calc_pnl_quote(pos, px2) == pos.quantity * (px2 - pos.avg_settle_price)
    @test Fastback.calc_return_quote(pos, px2) ≈ (px2 - px1) / px1
end

@testitem "Position short pnl/return" begin
    using Test, Fastback, Dates
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoBrokerProfile(), base_currency=base_currency);
    deposit!(acc, :USD, 100_000.0)
    TEST = register_instrument!(acc, spot_instrument(Symbol("TEST/USD"), :TEST, :USD))
    px1, px2 = 500.0, 505.0
    # short
    pos = Position{DateTime}(2, TEST; avg_entry_price=px1, avg_settle_price=px1, quantity=-500.0)
    @test !is_long(pos)
    @test is_short(pos)
    @test Fastback.calc_pnl_quote(pos, px2) == pos.quantity * (px2 - pos.avg_settle_price)
    @test Fastback.calc_return_quote(pos, px2) ≈ -(px2 - px1) / px1
end

@testitem "Position return remains sign-consistent at negative prices" begin
    using Test, Fastback, Dates
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoBrokerProfile(), base_currency=base_currency);
    deposit!(acc, :USD, 100_000.0)
    TEST = register_instrument!(acc, spot_instrument(Symbol("NEGRET/USD"), :NEGRET, :USD))

    entry = -10.0
    close = -5.0

    pos_long = Position{DateTime}(1, TEST; avg_entry_price=entry, avg_settle_price=entry, quantity=2.0)
    @test Fastback.calc_return_quote(pos_long, close) ≈ 0.5

    pos_short = Position{DateTime}(2, TEST; avg_entry_price=entry, avg_settle_price=entry, quantity=-2.0)
    @test Fastback.calc_return_quote(pos_short, close) ≈ -0.5
end

@testitem "calc_realized_qty" begin
    using Test, Fastback
    # Test 1: long position, sell order more than position
    @test Fastback.calc_realized_qty(10, -30) == 10
    # Test 2: long position, sell order less than position
    @test Fastback.calc_realized_qty(10, -5) == 5
    # Test 3: short position, buy order more than position
    @test Fastback.calc_realized_qty(-10, 30) == -10
    # Test 4: short position, buy order less than position
    @test Fastback.calc_realized_qty(-10, 5) == -5
    # Test 4: short position, buy order same as position
    @test Fastback.calc_realized_qty(-10, 10) == -10
    # Test 5: long position, buy order
    @test Fastback.calc_realized_qty(10, 5) == 0
    # Test 6: short position, sell order
    @test Fastback.calc_realized_qty(-10, -5) == 0
    # Test 7: no position, sell order
    @test Fastback.calc_realized_qty(0, -5) == 0
    # Test 8: no position, buy order
    @test Fastback.calc_realized_qty(0, 5) == 0
    # Test 9: no op
    @test Fastback.calc_realized_qty(0, 0) == 0
end

@testitem "calc_exposure_increase_quantity" begin
    using Test, Fastback
    # Test 1: long position, buy order more than position
    @test Fastback.calc_exposure_increase_quantity(10, 20) == 20
    # Test 2: long position, buy order less than position
    @test Fastback.calc_exposure_increase_quantity(10, 5) == 5
    # Test 3: short position, sell order more than position
    @test Fastback.calc_exposure_increase_quantity(-10, -20) == -20
    # Test 4: short position, sell order less than position
    @test Fastback.calc_exposure_increase_quantity(-10, -5) == -5
    # Test 5: long position, sell order
    @test Fastback.calc_exposure_increase_quantity(10, -5) == 0
    # Test 6: short position, buy order
    @test Fastback.calc_exposure_increase_quantity(-10, 5) == 0
    # Test 7: no position, sell order
    @test Fastback.calc_exposure_increase_quantity(0, -5) == -5
    # Test 8: no position, buy order
    @test Fastback.calc_exposure_increase_quantity(0, 5) == 5
    # Test 9: no op
    @test Fastback.calc_exposure_increase_quantity(0, 0) == 0
end

@testitem "margin ccy rejects invalid margin mode" begin
    using Test, Fastback

    bad_mode = Core.Intrinsics.bitcast(MarginMode.T, Int8(7))
    inst = Instrument(Symbol("BAD/USD"), :BAD, :USD;
        margin_mode=bad_mode,
        margin_init_long=1.0,
        margin_init_short=1.0,
        margin_maint_long=1.0,
        margin_maint_short=1.0,
    )

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoBrokerProfile(), mode=AccountMode.Margin, base_currency=base_currency)
    register_instrument!(acc, inst)

    @test_throws ArgumentError margin_init_margin_ccy(acc, inst, 1.0, 10.0)
    @test_throws ArgumentError margin_maint_margin_ccy(acc, inst, 1.0, 10.0)
end

@testitem "mark_price set on fills and marks" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoBrokerProfile(), mode=AccountMode.Margin, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)
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
    trade = fill_order!(acc, order; dt=order.date, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)
    pos = get_position(acc, inst)
    @test pos.mark_price == 100.0

    # Update with bid/ask; long uses bid as close
    update_marks!(acc, inst, order.date, 101.0, 102.0, 101.5)
    @test pos.mark_price == 101.0

    # Flip to short; mark on fill should update
    order2 = Order(oid!(acc), inst, DateTime(2026, 1, 2), 103.0, -2.0)
    fill_order!(acc, order2; dt=order2.date, fill_price=order2.price, bid=order2.price, ask=order2.price, last=order2.price)
    @test pos.mark_price == 103.0

    # For short, close price comes from ask
    update_marks!(acc, inst, order2.date, 98.0, 99.0, 98.5)
    @test pos.mark_price == 99.0
end
