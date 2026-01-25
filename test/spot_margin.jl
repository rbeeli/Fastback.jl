using TestItemRunner

@testitem "Spot on margin long uses leverage" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOTM/USD"),
        :SPOTM,
        :USD;
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.25,
        margin_init_short=0.5,
        margin_maint_short=0.25,
    ))
    @test is_margined_spot(inst)

    dt = DateTime(2025, 1, 1)
    price = 100.0
    qty = 200.0                # notional = 20_000

    trade = fill_order!(acc, Order(oid!(acc), inst, dt, price, qty), dt, price)
    @test trade isa Trade

    usd = cash_asset(acc, :USD)
    usd_idx = usd.index

    @test cash_balance(acc, usd) ≈ -10_000.0 atol=1e-8
    @test equity(acc, usd) ≈ 10_000.0 atol=1e-8
    @test init_margin_used(acc, usd) ≈ 10_000.0 atol=1e-8
    @test available_funds(acc, usd) ≈ 0.0 atol=1e-8
    @test maint_margin_used(acc, usd) ≈ 5_000.0 atol=1e-8

    # Balance can be negative while equity stays funded by the asset value
    @test acc.balances[usd_idx] < 0
    @test acc.equities[usd_idx] > 0
end

@testitem "Spot on margin short keeps equity, accrues borrow fees" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOTMS/USD"),
        :SPOTMS,
        :USD;
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.25,
        margin_init_short=0.5,
        margin_maint_short=0.25,
        short_borrow_rate=0.10,
    ))

    dt0 = DateTime(2025, 1, 1)
    price = 100.0
    qty = -200.0               # notional = 20_000

    trade = fill_order!(acc, Order(oid!(acc), inst, dt0, price, qty), dt0, price)
    @test trade isa Trade

    usd = cash_asset(acc, :USD)
    usd_idx = usd.index

    # Equity should remain the original deposit (no free lunch on borrowed proceeds)
    @test cash_balance(acc, usd) ≈ 30_000.0 atol=1e-8
    @test get_position(acc, inst).value_local ≈ -20_000.0 atol=1e-8
    @test equity(acc, usd) ≈ 10_000.0 atol=1e-8
    @test init_margin_used(acc, usd) ≈ 10_000.0 atol=1e-8

    # Start borrow-fee clock, then accrue one day
    accrue_borrow_fees!(acc, dt0)
    dt1 = dt0 + Day(1)
    accrue_borrow_fees!(acc, dt1)

    expected_fee = 20_000.0 * 0.10 / 365.0
    @test acc.balances[usd_idx] ≈ 30_000.0 - expected_fee atol=1e-6
    @test acc.equities[usd_idx] ≈ 10_000.0 - expected_fee atol=1e-6
    cf = only(acc.cashflows)
    @test cf.kind == CashflowKind.BorrowFee
    @test cf.cash_index == usd_idx
    @test cf.inst_index == inst.index
    @test cf.amount ≈ -expected_fee atol=1e-6
end
