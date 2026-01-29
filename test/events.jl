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
    fill_order!(acc, order; dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

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

@testitem "process_step! executes steps in documented order" begin
    using Test, Fastback, Dates

    er = SpotExchangeRates()
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD, margining_style=MarginingStyle.BaseCurrency, exchange_rates=er)

    usd = Cash(:USD)
    chf = Cash(:CHF)
    deposit!(acc, usd, 1_000.0)
    deposit!(acc, chf, 0.0)

    set_interest_rates!(acc, :USD; borrow=0.10, lend=0.0)
    set_interest_rates!(acc, :CHF; borrow=0.03, lend=0.0)
    update_rate!(er, cash_asset(acc, :USD), cash_asset(acc, :CHF), 1.0)

    dt0 = DateTime(2026, 1, 1)
    dt1 = dt0 + Day(1)

    spot_inst = register_instrument!(acc, Instrument(
        Symbol("SPOTORD/USDCHF"),
        :SPOTORD,
        :USD;
        settle_symbol=:CHF,
        settlement=SettlementStyle.Asset,
        contract_kind=ContractKind.Spot,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_maint_long=0.1,
        margin_init_short=0.1,
        margin_maint_short=0.1,
        multiplier=1.0,
    ))

    perp_inst = register_instrument!(acc, Instrument(
        Symbol("PERPORD/USD"),
        :PERPORD,
        :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_maint_long=0.1,
        margin_init_short=0.1,
        margin_maint_short=0.1,
        multiplier=1.0,
    ))

    fut_inst = register_instrument!(acc, Instrument(
        Symbol("FUTORD/USD"),
        :FUTORD,
        :USD;
        contract_kind=ContractKind.Future,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=2.0,
        margin_init_short=0.5,
        margin_maint_short=2.0,
        expiry=dt1,
        multiplier=1.0,
    ))

    spot_trade = fill_order!(acc, Order(oid!(acc), spot_inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    perp_trade = fill_order!(acc, Order(oid!(acc), perp_inst, dt0, 50.0, 1.0); dt=dt0, fill_price=50.0, bid=50.0, ask=50.0, last=50.0)
    fut_trade = fill_order!(acc, Order(oid!(acc), fut_inst, dt0, 100.0, 10.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    @test spot_trade isa Trade
    @test perp_trade isa Trade
    @test fut_trade isa Trade

    # Prime accrual clocks; do not change state otherwise.
    process_step!(acc, dt0)

    pre_deficit = maint_margin_used_base_ccy(acc) - equity_base_ccy(acc)
    @test pre_deficit > 0

    bal_chf_before = cash_balance(acc, chf)
    eq_chf_before = equity(acc, chf)
    spot_pos = get_position(acc, spot_inst)
    spot_value_before = spot_pos.value_settle

    fx_updates = [FXUpdate(usd.index, chf.index, 0.8)]
    marks = [
        MarkUpdate(spot_inst.index, 110.0, 110.0, 110.0),
        MarkUpdate(perp_inst.index, 60.0, 60.0, 60.0),
        MarkUpdate(fut_inst.index, 120.0, 120.0, 120.0),
    ]
    funding = [FundingUpdate(perp_inst.index, 0.01)]

    process_step!(acc, dt1; fx_updates=fx_updates, marks=marks, funding=funding, liquidate=true)

    yearfrac = Dates.value(Dates.Millisecond(dt1 - dt0)) / (1000 * 60 * 60 * 24 * 365.0)
    expected_chf_interest = bal_chf_before * 0.03 * yearfrac
    expected_spot_value = to_settle(
        acc,
        spot_inst,
        value_quote(spot_inst, spot_pos.quantity, 110.0, spot_pos.avg_entry_price),
    )
    expected_spot_mark = expected_spot_value - spot_value_before
    expected_funding = -60.0 * 0.01
    expected_perp_vm = 10.0
    expected_fut_vm = 200.0

    @test cash_balance(acc, chf) ≈ bal_chf_before + expected_chf_interest atol=1e-8
    @test equity(acc, chf) ≈ eq_chf_before + expected_chf_interest + expected_spot_mark atol=1e-8

    @test length(acc.cashflows) == 4
    kinds = getfield.(acc.cashflows, :kind)
    @test kinds == [
        CashflowKind.VariationMargin,
        CashflowKind.VariationMargin,
        CashflowKind.Funding,
        CashflowKind.Interest,
    ]

    vm_perp_cf = acc.cashflows[1]
    vm_fut_cf = acc.cashflows[2]
    funding_cf = acc.cashflows[3]
    interest_cf = acc.cashflows[4]

    @test interest_cf.amount ≈ expected_chf_interest atol=1e-8
    @test vm_perp_cf.amount ≈ expected_perp_vm atol=1e-8
    @test vm_fut_cf.amount ≈ expected_fut_vm atol=1e-8
    @test funding_cf.amount ≈ expected_funding atol=1e-8

    @test get_position(acc, fut_inst).quantity == 0.0
    @test !is_under_maintenance(acc)
    @test all(t.reason != TradeReason.Liquidation for t in acc.trades)
    @test count(t -> t.reason == TradeReason.Expiry, acc.trades) == 1
end

@testitem "process_step! revalues cross-currency positions on FX updates" begin
    using Test, Fastback, Dates

    er = SpotExchangeRates()
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD, exchange_rates=er)

    usd = Cash(:USD)
    chf = Cash(:CHF)
    deposit!(acc, usd, 0.0)
    deposit!(acc, chf, 1_000.0)
    update_rate!(er, cash_asset(acc, :USD), cash_asset(acc, :CHF), 1.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("FXREVAL/USDCHF"),
        :FXREVAL,
        :USD;
        settle_symbol=:CHF,
        settlement=SettlementStyle.Asset,
        contract_kind=ContractKind.Spot,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_maint_long=0.05,
        margin_init_short=0.1,
        margin_maint_short=0.05,
        multiplier=1.0,
    ))

    dt0 = DateTime(2026, 1, 1)
    dt1 = dt0 + Day(1)

    order = Order(oid!(acc), inst, dt0, 100.0, 1.0)
    fill_order!(acc, order; dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    process_step!(acc, dt0) # initialize accrual clocks

    pos = get_position(acc, inst)
    eq_before = equity(acc, chf)
    init_before = init_margin_used(acc, chf)
    value_before = pos.value_settle

    fx_updates = [FXUpdate(usd.index, chf.index, 0.8)]
    process_step!(acc, dt1; fx_updates=fx_updates)

    pos_after = get_position(acc, inst)
    expected_value = to_settle(acc, inst, pos_after.value_quote)
    expected_eq = eq_before + (expected_value - value_before)
    expected_init = margin_init_settle(acc, inst, pos_after.quantity, pos_after.last_price)

    @test pos_after.value_settle ≈ expected_value atol=1e-12
    @test equity(acc, chf) ≈ expected_eq atol=1e-12
    @test init_margin_used(acc, chf) ≈ expected_init atol=1e-12
    @test init_margin_used(acc, chf) < init_before
end

@testitem "process_step! accrues borrow fees using latest mark in step" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 50_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("BORROW/USD"),
            :BORROW,
            :USD;
            settlement=SettlementStyle.Asset,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.1,
            margin_maint_short=0.1,
            short_borrow_rate=0.50,
        ),
    )

    dt0 = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt0, 100.0, -10.0)
    fill_order!(acc, order; dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    # initialize accrual clocks
    process_step!(acc, dt0)

    dt1 = dt0 + Day(1)
    marks = [MarkUpdate(inst.index, 120.0, 120.0, 120.0)]

    bal_before = cash_balance(acc, usd)
    process_step!(acc, dt1; marks=marks)
    bal_after = cash_balance(acc, usd)

    yearfrac = 1 / 365
    expected_fee = abs(-10.0) * 120.0 * inst.multiplier * inst.short_borrow_rate * yearfrac

    @test bal_before - bal_after ≈ expected_fee atol=1e-10

    borrow_cfs = filter(cf -> cf.kind == CashflowKind.BorrowFee, acc.cashflows)
    @test length(borrow_cfs) == 1
    borrow_cf = only(borrow_cfs)
    @test borrow_cf.amount ≈ -expected_fee atol=1e-10
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
    fill_order!(acc, order; dt=dt_open, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    @test get_position(acc, inst).quantity == 1.0

    commission_pct = 0.01
    trades = process_expiries!(acc, dt_exp; commission_pct=commission_pct)
    trade = only(trades)
    @test trade.reason == TradeReason.Expiry
    @test trade.commission_settle ≈ 100.0 * 1.0 * commission_pct atol=1e-8
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
    fill_order!(acc, order; dt=dt_open, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    @test get_position(acc, inst).quantity == 2.0
    @test init_margin_used(acc, usd) > 0

    # Final mark at expiry
    update_marks!(acc, inst, dt_exp, 110.0, 110.0, 110.0)
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
    @test trade.cash_delta_settle ≈ 0.0 atol=1e-10

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
    fill_order!(acc, order; dt=dt_open, fill_price=50.0, bid=50.0, ask=50.0, last=50.0)
    update_marks!(acc, inst, dt_exp, 55.0, 55.0, 55.0)

    @test_throws ArgumentError process_expiries!(acc, dt_exp; physical_expiry_policy=PhysicalExpiryPolicy.Error)
    @test get_position(acc, inst).quantity == 1.0

    trades = process_expiries!(acc, dt_exp; physical_expiry_policy=PhysicalExpiryPolicy.Close)
    @test length(trades) == 1
    @test get_position(acc, inst).quantity == 0.0
end
