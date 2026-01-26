using TestItemRunner

@testitem "process_step! accrual is idempotent for repeated timestamps" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 10_000.0)
    set_interest_rates!(acc, :USD; borrow=0.10, lend=0.05)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("SHRT/USD"),
            :SHRT,
            :USD;
            settlement=SettlementStyle.Asset,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
            short_borrow_rate=0.20,
        ),
    )

    dt0 = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt0, 100.0, -5.0)
    fill_order!(acc, order, dt0, 100.0)

    # initialize accrual clocks
    process_step!(acc, dt0)

    bal_before = cash_balance(acc, usd)
    dt1 = dt0 + Day(1)

    process_step!(acc, dt1)
    bal_after_first = cash_balance(acc, usd)
    eq_after_first = equity(acc, usd)
    cf_count = length(acc.cashflows)

    yearfrac = 1 / 365
    rate = bal_before >= 0 ? 0.05 : 0.10
    expected_interest = bal_before * rate * yearfrac
    pos = get_position(acc, inst)
    expected_borrow = abs(pos.quantity) * pos.mark_price * inst.multiplier * 0.20 * yearfrac
    @test bal_after_first - bal_before ≈ (expected_interest - expected_borrow) atol=1e-8

    process_step!(acc, dt1)
    @test cash_balance(acc, usd) ≈ bal_after_first atol=1e-12
    @test equity(acc, usd) ≈ eq_after_first atol=1e-12
    @test length(acc.cashflows) == cf_count
end

@testitem "process_step! rejects backward time" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 1_000.0)
    set_interest_rates!(acc, :USD; borrow=0.05, lend=0.02)

    dt1 = DateTime(2026, 1, 1)
    process_step!(acc, dt1)

    dt0 = dt1 - Day(1)
    @test_throws ArgumentError process_step!(acc, dt0)
end

@testitem "process_expiries! forwards commission_pct to expiry fill" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 5_000.0)

    dt_open = DateTime(2026, 1, 1)
    dt_exp = dt_open + Day(7)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("FUT/USD"),
            :FUT,
            :USD;
            contract_kind=ContractKind.Future,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_maint_long=0.05,
            expiry=dt_exp,
        ),
    )

    order = Order(oid!(acc), inst, dt_open, 100.0, 1.0)
    fill_order!(acc, order, dt_open, 100.0)
    @test get_position(acc, inst).quantity == 1.0

    commission_pct = 0.01
    trades = process_expiries!(acc, dt_exp; commission_pct=commission_pct)
    trade = only(trades)
    @test trade.reason == TradeReason.Expiry
    @test trade.commission ≈ 100.0 * 1.0 * commission_pct atol=1e-8
    @test get_position(acc, inst).quantity == 0.0
end

@testitem "Futures expiry auto-closes with no extra PnL beyond last variation settlement" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 20_000.0)

    dt_open = DateTime(2026, 1, 1)
    dt_exp = dt_open + Day(5)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("FUT2/USD"),
            :FUT2,
            :USD;
            contract_kind=ContractKind.Future,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_maint_long=0.05,
            expiry=dt_exp,
        ),
    )

    order = Order(oid!(acc), inst, dt_open, 100.0, 2.0)
    fill_order!(acc, order, dt_open, 100.0)
    @test get_position(acc, inst).quantity == 2.0
    @test init_margin_used(acc, usd) > 0

    # Final mark at expiry
    update_marks!(acc, inst; dt=dt_exp, bid=110.0, ask=110.0)
    eq_before = equity(acc, usd)
    cash_before = cash_balance(acc, usd)
    init_before = init_margin_used(acc, usd)
    maint_before = maint_margin_used(acc, usd)
    @test init_before > 0
    @test maint_before > 0

    trades = process_expiries!(acc, dt_exp)
    @test length(trades) == 1
    trade = only(trades)
    @test trade.reason == TradeReason.Expiry
    @test trade.cash_delta ≈ 0.0 atol=1e-10

    pos = get_position(acc, inst)
    @test pos.quantity == 0.0
    @test init_margin_used(acc, usd) ≈ 0.0 atol=1e-10
    @test maint_margin_used(acc, usd) ≈ 0.0 atol=1e-10
    @test equity(acc, usd) ≈ eq_before atol=1e-10
    @test cash_balance(acc, usd) ≈ cash_before atol=1e-10
end

@testitem "Physical-delivery futures can be refused via physical_expiry_policy" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 10_000.0)

    dt_open = DateTime(2026, 1, 1)
    dt_exp = dt_open + Day(2)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("FUT/PHYEXPIRE"),
            :FUT,
            :USD;
            contract_kind=ContractKind.Future,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_maint_long=0.05,
            delivery_style=DeliveryStyle.PhysicalDeliver,
            expiry=dt_exp,
        ),
    )

    order = Order(oid!(acc), inst, dt_open, 50.0, 1.0)
    fill_order!(acc, order, dt_open, 50.0)
    update_marks!(acc, inst; dt=dt_exp, bid=55.0, ask=55.0)

    @test_throws ArgumentError process_expiries!(acc, dt_exp; physical_expiry_policy=PhysicalExpiryPolicy.Error)
    @test get_position(acc, inst).quantity == 1.0

    trades = process_expiries!(acc, dt_exp; physical_expiry_policy=PhysicalExpiryPolicy.Close)
    @test length(trades) == 1
    @test get_position(acc, inst).quantity == 0.0
end
