using TestItemRunner

@testitem "short borrow fees accrue on asset-settled shorts" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 5_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("SHORT/USD"), :SHORT, :USD;
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1, margin_init_short=0.1,
        margin_maint_long=0.05, margin_maint_short=0.05,
        short_borrow_rate=0.1))

    dt0 = DateTime(2025, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, -10.0), dt0, 100.0)

    accrue_borrow_fees!(acc, dt0) # initialize clock

    before_bal = acc.balances[inst.quote_cash_index]
    dt1 = dt0 + Year(1)
    accrue_borrow_fees!(acc, dt1)
    after_bal = acc.balances[inst.quote_cash_index]

    fee = before_bal - after_bal
    @test fee ≈ 10 * 100.0 * 0.1 atol=1e-6
    @test get_position(acc, inst).quantity == -10.0
end
