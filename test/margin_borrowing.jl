using Dates
using TestItemRunner

@testitem "margin account allows exposure on margin-enabled instrument" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoBrokerProfile(), mode=AccountMode.Margin, base_currency=base_currency)
    deposit!(acc, :USD, 6_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("MARGINABLE/USD"),
        :MARGINABLE,
        :USD;
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 100.0, 100.0)
    trade = fill_order!(acc, order; dt=dt, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)

    @test trade isa Trade
    pos = get_position(acc, inst)
    @test pos.quantity == 100.0
    @test cash_balance(acc, cash_asset(acc, :USD)) ≈ -4_000.0
    @test equity(acc, cash_asset(acc, :USD)) ≈ 6_000.0
    @test init_margin_used(acc, cash_asset(acc, :USD)) ≈ 5_000.0
end

@testitem "non-marginable instruments are rejected" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoBrokerProfile(), mode=AccountMode.Margin, base_currency=base_currency)
    deposit!(acc, :USD, 6_000.0)

    inst = Instrument(
        Symbol("CASHONLY/USD"),
        :CASHONLY,
        :USD;
        margin_mode=MarginMode.None,
    )

    @test_throws ArgumentError register_instrument!(acc, inst)
end

@testitem "risk-reducing trades bypass initial margin check" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoBrokerProfile(), mode=AccountMode.Margin, base_currency=base_currency)
    deposit!(acc, :USD, 1_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("DERISK/USD"),
        :DERISK,
        :USD;
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.5,
        margin_maint_short=0.5,
    ))

    dt_open = DateTime(2026, 1, 1)
    open_order = Order(oid!(acc), inst, dt_open, 100.0, 20.0)
    open_trade = fill_order!(acc, open_order; dt=dt_open, fill_price=open_order.price, bid=open_order.price, ask=open_order.price, last=open_order.price)
    @test open_trade isa Trade

    pos = get_position(acc, inst)
    # Mark the position down sharply to become under-margined
    update_marks!(acc, pos, dt_open, 30.0, 30.0, 30.0)

    @test equity(acc, cash_asset(acc, :USD)) < init_margin_used(acc, cash_asset(acc, :USD))

    dt_reduce = dt_open + Day(1)
    reduce_order = Order(oid!(acc), inst, dt_reduce, 30.0, -5.0)
    reduce_trade = fill_order!(acc, reduce_order; dt=dt_reduce, fill_price=reduce_order.price, bid=reduce_order.price, ask=reduce_order.price, last=reduce_order.price)

    @test reduce_trade isa Trade
    @test pos.quantity == 15.0
    @test init_margin_used(acc, cash_asset(acc, :USD)) ≈ margin_init_margin_ccy(acc, inst, pos.quantity, reduce_order.price)
end
