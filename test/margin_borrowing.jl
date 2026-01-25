using Dates
using TestItemRunner

@testitem "margin account allows borrowing on margin-enabled instrument" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 6_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("MARGINABLE/USD"),
        :MARGINABLE,
        :USD;
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.25,
    ))

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 100.0, 100.0)
    trade = fill_order!(acc, order, dt, order.price)

    @test trade isa Trade
    pos = get_position(acc, inst)
    @test pos.quantity == 100.0
    @test cash_balance(acc, :USD) ≈ -4_000.0
    @test equity(acc, :USD) ≈ 6_000.0
    @test init_margin_used(acc, :USD) ≈ 5_000.0
end

@testitem "non-marginable instrument stays cash-funded inside margin account" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 6_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("CASHONLY/USD"),
        :CASHONLY,
        :USD;
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.None,
    ))

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 100.0, 100.0)
    result = fill_order!(acc, order, dt, order.price)

    @test result == OrderRejectReason.InsufficientCash
    @test isempty(acc.trades)
    pos = get_position(acc, inst)
    @test pos.quantity == 0.0
    @test cash_balance(acc, :USD) == 6_000.0
end

@testitem "risk-reducing trades bypass initial margin check" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 1_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("DERISK/USD"),
        :DERISK,
        :USD;
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.5,
    ))

    dt_open = DateTime(2026, 1, 1)
    open_order = Order(oid!(acc), inst, dt_open, 100.0, 20.0)
    open_trade = fill_order!(acc, open_order, dt_open, open_order.price)
    @test open_trade isa Trade

    pos = get_position(acc, inst)
    # Mark the position down sharply to become under-margined
    update_marks!(acc, pos; dt=dt_open, close_price=30.0)

    @test equity(acc, :USD) < init_margin_used(acc, :USD)

    dt_reduce = dt_open + Day(1)
    reduce_order = Order(oid!(acc), inst, dt_reduce, 30.0, -5.0)
    reduce_trade = fill_order!(acc, reduce_order, dt_reduce, reduce_order.price)

    @test reduce_trade isa Trade
    @test pos.quantity == 15.0
    @test init_margin_used(acc, :USD) ≈ margin_init_quote(inst, pos.quantity, reduce_order.price)
end
