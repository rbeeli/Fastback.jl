using TestItemRunner

@testitem "liquidate_all! closes all positions with liquidation reason" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    inst1 = register_instrument!(acc, Instrument(Symbol("A/USD"), :A, :USD; margin_mode=MarginMode.PercentNotional, margin_init_long=0.1, margin_maint_long=0.05))
    inst2 = register_instrument!(acc, Instrument(Symbol("B/USD"), :B, :USD; margin_mode=MarginMode.PercentNotional, margin_init_long=0.1, margin_maint_long=0.05))

    dt = DateTime(2024, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst1, dt, 100.0, 10.0), dt, 100.0)
    fill_order!(acc, Order(oid!(acc), inst2, dt, 50.0, 20.0), dt, 50.0)

    trades = liquidate_all!(acc, dt; commission=0.0)

    @test all(pos.quantity == 0.0 for pos in acc.positions)
    @test all(t.reason == TradeReason.Liquidation for t in trades)
    @test all(x -> x == 0.0, acc.init_margin_used)
    @test all(x -> x == 0.0, acc.maint_margin_used)
end
