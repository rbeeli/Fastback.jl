using TestItemRunner

@testitem "Trade reasons default to Normal" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 1_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("ABC/USD"), :ABC, :USD))

    dt = DateTime(2024, 1, 1)
    trade = fill_order!(acc, Order(oid!(acc), inst, dt, 10.0, 1.0); dt=dt, fill_price=10.0, bid=10.0, ask=10.0, last=10.0)
    @test trade isa Trade
    @test trade.reason == TradeReason.Normal
end

@testitem "Expiry trades are tagged as Expiry" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 1_000.0)
    inst = register_instrument!(acc, Instrument(
        Symbol("EXP/USD"),
        :EXP,
        :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        expiry=DateTime(2024, 1, 2),
    ))

    dt_open = DateTime(2024, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt_open, 10.0, 1.0); dt=dt_open, fill_price=10.0, bid=10.0, ask=10.0, last=10.0)

    dt_settle = DateTime(2024, 1, 3)
    trade = settle_expiry!(acc, inst, dt_settle; settle_price=9.0)
    @test trade isa Trade
    @test trade.reason == TradeReason.Expiry
end
