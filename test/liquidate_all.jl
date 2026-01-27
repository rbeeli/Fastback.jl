using TestItemRunner

@testitem "liquidate_all! closes all positions with liquidation reason" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    inst1 = register_instrument!(acc, Instrument(Symbol("A/USD"), :A, :USD; margin_mode=MarginMode.PercentNotional, margin_init_long=0.1, margin_maint_long=0.05))
    inst2 = register_instrument!(acc, Instrument(Symbol("B/USD"), :B, :USD; margin_mode=MarginMode.PercentNotional, margin_init_long=0.1, margin_maint_long=0.05))

    dt = DateTime(2024, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst1, dt, 100.0, 10.0); dt=dt, fill_price=100.0)
    fill_order!(acc, Order(oid!(acc), inst2, dt, 50.0, 20.0); dt=dt, fill_price=50.0)

    trades = liquidate_all!(acc, dt; commission=0.0)

    @test all(pos.quantity == 0.0 for pos in acc.positions)
    @test all(t.reason == TradeReason.Liquidation for t in trades)
    @test all(x -> x == 0.0, acc.init_margin_used)
    @test all(x -> x == 0.0, acc.maint_margin_used)
end

@testitem "liquidate_all! applies commission percentage" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 5_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("C/USD"), :C, :USD; margin_mode=MarginMode.PercentNotional, margin_init_long=0.1, margin_maint_long=0.05))

    dt = DateTime(2024, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt, 100.0, 10.0); dt=dt, fill_price=100.0)

    trades = liquidate_all!(acc, dt; commission=2.0, commission_pct=0.01)

    @test length(trades) == 1
    @test trades[1].commission_settle ≈ 12.0  # 2 fixed + 1% of 100*10
    @test trades[1].reason == TradeReason.Liquidation
    @test get_position(acc, inst).quantity == 0.0
end
