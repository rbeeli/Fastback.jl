using Dates
using TestItemRunner

@testitem "Perpetual funding debits longs and credits shorts" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), mode=AccountMode.Margin, base_currency=base_currency)
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000.0)

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
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
        ),
    )

    dt = DateTime(2026, 1, 1)
    open_price = 100.0
    long_order = Order(oid!(acc), inst, dt, open_price, 1.0)
    fill_order!(acc, long_order; dt=dt, fill_price=open_price, bid=open_price, ask=open_price, last=open_price)

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
    fill_order!(acc, close_order; dt=dt + Day(1), fill_price=open_price, bid=open_price, ask=open_price, last=open_price)
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

@testitem "Perpetual funding uses mark price" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), mode=AccountMode.Margin, base_currency=base_currency)
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("PERPMARK/USD"),
            :PERPMARK,
            :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
            multiplier=1.0,
        ),
    )

    dt0 = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    dt1 = dt0 + Hour(1)
    update_marks!(acc, inst, dt1, 99.0, 101.0, 105.0) # mark(mid)=100, last=105

    funding_rate = 0.01
    apply_funding!(acc, inst, dt1 + Hour(8); funding_rate=funding_rate)

    expected_payment = -1.0 * 100.0 * inst.multiplier * funding_rate
    @test cash_balance(acc, usd) ≈ 1_000.0 + expected_payment atol=1e-8
    @test equity(acc, usd) ≈ cash_balance(acc, usd) atol=1e-8
end

@testitem "Perpetual funding uses absolute price when market is negative" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), mode=AccountMode.Margin, base_currency=base_currency)
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("PERPNEG/USD"),
            :PERPNEG,
            :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
            multiplier=1.0,
        ),
    )

    dt = DateTime(2026, 1, 1)
    negative_price = -100.0
    funding_rate = 0.01

    fill_order!(
        acc,
        Order(oid!(acc), inst, dt, negative_price, 1.0);
        dt=dt,
        fill_price=negative_price,
        bid=negative_price,
        ask=negative_price,
        last=negative_price,
    )

    apply_funding!(acc, inst, dt + Hour(8); funding_rate=funding_rate)
    cf_long = acc.cashflows[end]
    expected_long_payment = -abs(negative_price) * inst.multiplier * funding_rate
    @test cf_long.amount ≈ expected_long_payment atol=1e-8

    fill_order!(
        acc,
        Order(oid!(acc), inst, dt + Day(1), negative_price, -2.0);
        dt=dt + Day(1),
        fill_price=negative_price,
        bid=negative_price,
        ask=negative_price,
        last=negative_price,
    )
    apply_funding!(acc, inst, dt + Day(1) + Hour(8); funding_rate=funding_rate)
    cf_short = acc.cashflows[end]
    expected_short_payment = abs(negative_price) * inst.multiplier * funding_rate
    @test cf_short.amount ≈ expected_short_payment atol=1e-8
end
