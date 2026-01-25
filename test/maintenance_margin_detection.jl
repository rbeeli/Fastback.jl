using TestItemRunner

@testitem "Maintenance margin breach is detected" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 500.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOT/USD"),
        :SPOT,
        :USD;
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.25,
    ))

    dt = DateTime(2024, 1, 1)
    price = 100.0
    qty = 10.0

    trade = fill_order!(acc, Order(oid!(acc), inst, dt, price, qty), dt, price)
    @test trade isa Trade

    # Mark price down to trigger maintenance breach: PnL = (20-100)*10 = -800, equity = 200 < maint 250
    update_marks!(acc, inst; dt=dt, bid=20.0, ask=20.0)

    @test is_under_maintenance(acc) == true
    @test maint_deficit_base_ccy(acc) > 0
end
