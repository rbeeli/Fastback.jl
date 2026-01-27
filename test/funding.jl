using Dates
using TestItemRunner

@testitem "Perpetual funding debits longs and credits shorts" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 1_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("PERP/USD"),
            :PERP,
            :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_maint_long=0.05,
        ),
    )

    dt = DateTime(2026, 1, 1)
    open_price = 100.0
    long_order = Order(oid!(acc), inst, dt, open_price, 1.0)
    fill_order!(acc, long_order; dt=dt, fill_price=open_price)

    funding_rate = 0.01
    apply_funding!(acc, inst, dt + Hour(8); funding_rate=funding_rate)

    expected_payment = -1.0 * open_price * inst.multiplier * funding_rate
    @test cash_balance(acc, usd) ≈ 1_000.0 + expected_payment atol=1e-8
    @test equity(acc, usd) ≈ cash_balance(acc, usd) atol=1e-8
    cf1 = only(acc.cashflows)
    @test cf1.kind == CashflowKind.Funding
    @test cf1.cash_index == inst.settle_cash_index
    @test cf1.inst_index == inst.index
    @test cf1.amount ≈ expected_payment atol=1e-8

    # Flip to short and apply funding again (short should receive)
    close_order = Order(oid!(acc), inst, dt + Day(1), open_price, -2.0)
    fill_order!(acc, close_order; dt=dt + Day(1), fill_price=open_price)
    apply_funding!(acc, inst, dt + Day(1) + Hour(8); funding_rate=funding_rate)

    pos = get_position(acc, inst)
    @test pos.quantity ≈ -1.0
    expected_payment2 = -pos.quantity * open_price * inst.multiplier * funding_rate
    @test cash_balance(acc, usd) ≈ 1_000.0 + expected_payment + expected_payment2 atol=1e-8
    @test equity(acc, usd) ≈ cash_balance(acc, usd) atol=1e-8
    @test length(acc.cashflows) == 2
    cf2 = acc.cashflows[end]
    @test cf2.amount ≈ expected_payment2 atol=1e-8
    @test cf2.kind == CashflowKind.Funding
end
