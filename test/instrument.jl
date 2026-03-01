using Dates
using TestItemRunner

@testitem "Instrument contract kinds and lifecycle" begin
    using Test, Fastback, Dates

    # Defaults to spot with open-ended lifecycle
    spot = InstrumentSpec(Symbol("SPOT/USD"), :SPOT, :USD)
    spot_inst = Instrument(1, 1, 1, 1, spot)
    @test spot.contract_kind == ContractKind.Spot
    @test spot.start_time == DateTime(0)
    @test spot.expiry == DateTime(0)
    @test !has_expiry(spot_inst)
    @test is_active(spot_inst, DateTime(2026, 1, 1))
    @test !is_expired(spot_inst, DateTime(2026, 1, 1))

    # Expiring future between start_time and expiry
    start_dt = DateTime(2026, 2, 1)
    expiry_dt = DateTime(2026, 6, 1)
    future = InstrumentSpec(
        Symbol("FUT/USD"),
        :FUT,
        :USD;
        contract_kind=ContractKind.Future,
        start_time=start_dt,
        expiry=expiry_dt,
    )
    future_inst = Instrument(2, 1, 1, 1, future)
    @test future.contract_kind == ContractKind.Future
    @test has_expiry(future_inst)
    @test !is_active(future_inst, start_dt - Day(1))
    @test is_active(future_inst, start_dt)
    @test is_active(future_inst, expiry_dt - Day(1))
    @test is_expired(future_inst, expiry_dt)
    @test !is_active(future_inst, expiry_dt + Day(1))

    # Perpetual with date-based time type and delayed activation
    start_date = Date(2026, 3, 15)
    perp = InstrumentSpec(
        Symbol("PERP/USD"),
        :PERP,
        :USD;
        contract_kind=ContractKind.Perpetual,
        time_type=Date,
        start_time=start_date,
    )
    perp_inst = Instrument(3, 1, 1, 1, perp)
    @test perp.contract_kind == ContractKind.Perpetual
    @test perp.start_time == start_date
    @test perp.expiry == Date(0)
    @test !has_expiry(perp_inst)
    @test !is_active(perp_inst, start_date - Day(1))
    @test is_active(perp_inst, start_date)
end

@testitem "ensure_active enforces lifecycle bounds" begin
    using Test, Fastback, Dates

    start_dt = DateTime(2026, 2, 1)
    expiry_dt = DateTime(2026, 3, 1)
    fut = InstrumentSpec(
        Symbol("ENSURE/USD"),
        :ENSURE,
        :USD;
        contract_kind=ContractKind.Future,
        start_time=start_dt,
        expiry=expiry_dt,
    )
    fut_inst = Instrument(1, 1, 1, 1, fut)

    @test_throws ArgumentError ensure_active(fut_inst, start_dt - Day(1))
    @test ensure_active(fut_inst, start_dt) === fut_inst
    @test_throws ArgumentError ensure_active(fut_inst, expiry_dt)
end

@testitem "symbol helper supports instrument and order" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    inst = register_instrument!(acc, InstrumentSpec(Symbol("BTC/USD"), :BTC, :USD;
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))
    order = Order(1, inst, DateTime(2026, 1, 1), 100.0, 1.0)

    @test symbol(inst) == Symbol("BTC/USD")
    @test symbol(order) == Symbol("BTC/USD")
end

@testitem "calc_base_qty_for_notional rounds to base_tick and clamps to base bounds" begin
    using Test, Fastback

    inst = Instrument(
        1,
        1,
        1,
        1,
        InstrumentSpec(
            Symbol("QTY/USD"),
            :QTY,
            :USD;
            base_tick=1.0,
            base_min=0.0,
            base_max=10.0,
            multiplier=5.0,
        ),
    )

    @test calc_base_qty_for_notional(inst, 100.0, 2_499.0) == 4.0
    @test calc_base_qty_for_notional(inst, 100.0, 2_500.0) == 5.0
    @test calc_base_qty_for_notional(inst, 100.0, 999_999.0) == 10.0
    @test calc_base_qty_for_notional(inst, 100.0, -500.0) == 0.0

    inst_signed = Instrument(
        2,
        1,
        1,
        1,
        InstrumentSpec(
            Symbol("QTYSGN/USD"),
            :QTYSGN,
            :USD;
            base_tick=1.0,
            base_min=-10.0,
            base_max=10.0,
            multiplier=5.0,
        ),
    )

    @test calc_base_qty_for_notional(inst_signed, 100.0, -2_550.0) == -5.0
    @test calc_base_qty_for_notional(inst_signed, -100.0, 2_550.0) == 5.0

    inst_fractional = Instrument(
        3,
        1,
        1,
        1,
        InstrumentSpec(
            Symbol("QTYFRAC/USD"),
            :QTYFRAC,
            :USD;
            base_tick=0.25,
            multiplier=1.0,
        ),
    )
    @test calc_base_qty_for_notional(inst_fractional, 10.0, 37.0) ≈ 3.5
end
