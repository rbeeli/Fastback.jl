using Dates
using TestItemRunner

@testitem "Instrument contract kinds and lifecycle" begin
    using Test, Fastback, Dates

    # Defaults to spot with open-ended lifecycle
    spot = Instrument(Symbol("SPOT/USD"), :SPOT, :USD)
    @test spot.contract_kind == ContractKind.Spot
    @test spot.start_time == DateTime(0)
    @test spot.expiry == DateTime(0)
    @test !has_expiry(spot)
    @test is_active(spot, DateTime(2026, 1, 1))
    @test !is_expired(spot, DateTime(2026, 1, 1))

    # Expiring future between start_time and expiry
    start_dt = DateTime(2026, 2, 1)
    expiry_dt = DateTime(2026, 6, 1)
    future = Instrument(
        Symbol("FUT/USD"),
        :FUT,
        :USD;
        contract_kind=ContractKind.Future,
        start_time=start_dt,
        expiry=expiry_dt,
    )
    @test future.contract_kind == ContractKind.Future
    @test has_expiry(future)
    @test !is_active(future, start_dt - Day(1))
    @test is_active(future, start_dt)
    @test is_active(future, expiry_dt - Day(1))
    @test is_expired(future, expiry_dt)
    @test !is_active(future, expiry_dt + Day(1))

    # Perpetual with date-based time type and delayed activation
    start_date = Date(2026, 3, 15)
    perp = Instrument(
        Symbol("PERP/USD"),
        :PERP,
        :USD;
        contract_kind=ContractKind.Perpetual,
        time_type=Date,
        start_time=start_date,
    )
    @test perp.contract_kind == ContractKind.Perpetual
    @test perp.start_time == start_date
    @test perp.expiry == Date(0)
    @test !has_expiry(perp)
    @test !is_active(perp, start_date - Day(1))
    @test is_active(perp, start_date)
end

@testitem "ensure_active enforces lifecycle bounds" begin
    using Test, Fastback, Dates

    start_dt = DateTime(2026, 2, 1)
    expiry_dt = DateTime(2026, 3, 1)
    fut = Instrument(
        Symbol("ENSURE/USD"),
        :ENSURE,
        :USD;
        contract_kind=ContractKind.Future,
        start_time=start_dt,
        expiry=expiry_dt,
    )

    @test_throws ArgumentError ensure_active(fut, start_dt - Day(1))
    @test ensure_active(fut, start_dt) === fut
    @test_throws ArgumentError ensure_active(fut, expiry_dt)
end

@testitem "symbol helper supports instrument and order" begin
    using Test, Fastback, Dates

    inst = Instrument(Symbol("BTC/USD"), :BTC, :USD)
    order = Order(1, inst, DateTime(2026, 1, 1), 100.0, 1.0)

    @test symbol(inst) == Symbol("BTC/USD")
    @test symbol(order) == Symbol("BTC/USD")
end

@testitem "calc_base_qty_for_notional rounds to base_tick and clamps to base bounds" begin
    using Test, Fastback

    inst = Instrument(
        Symbol("QTY/USD"),
        :QTY,
        :USD;
        base_tick=1.0,
        base_min=0.0,
        base_max=10.0,
        multiplier=5.0,
    )

    @test calc_base_qty_for_notional(inst, 100.0, 2_499.0) == 4.0
    @test calc_base_qty_for_notional(inst, 100.0, 2_500.0) == 5.0
    @test calc_base_qty_for_notional(inst, 100.0, 999_999.0) == 10.0
    @test calc_base_qty_for_notional(inst, 100.0, -500.0) == 0.0

    inst_signed = Instrument(
        Symbol("QTYSGN/USD"),
        :QTYSGN,
        :USD;
        base_tick=1.0,
        base_min=-10.0,
        base_max=10.0,
        multiplier=5.0,
    )

    @test calc_base_qty_for_notional(inst_signed, 100.0, -2_550.0) == -5.0
    @test calc_base_qty_for_notional(inst_signed, -100.0, 2_550.0) == 5.0

    inst_fractional = Instrument(
        Symbol("QTYFRAC/USD"),
        :QTYFRAC,
        :USD;
        base_tick=0.25,
        multiplier=1.0,
    )
    @test calc_base_qty_for_notional(inst_fractional, 10.0, 37.0) ≈ 3.5
end
