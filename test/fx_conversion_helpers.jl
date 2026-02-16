using TestItemRunner

@testitem "FX conversions centralize quote→settle→base flows" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(; funding=AccountFunding.Margined, base_currency=base_currency, margin_aggregation=MarginAggregation.BaseCurrency, exchange_rates=er, broker=FlatFeeBroker(fixed=1.0))

    deposit!(acc, :USD, 50_000.0)
    register_cash_asset!(acc, CashSpec(:CHF))
    deposit!(acc, :CHF, 1_000.0)

    usd_to_chf = 0.9
    update_rate!(er, cash_asset(acc, :USD), cash_asset(acc, :CHF), usd_to_chf)

    spot_inst = register_instrument!(acc, Instrument(
        Symbol("SPOT/USDCHF"),
        :SPOT,
        :USD;
        settle_symbol=:CHF,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.2,
        margin_init_short=0.2,
        margin_maint_long=0.1,
        margin_maint_short=0.1,
        short_borrow_rate=0.1,
        multiplier=1.0,
    ))
    pos_spot = get_position(acc, spot_inst)
    chf_idx = spot_inst.settle_cash_index
    margin_idx = spot_inst.margin_cash_index

    dt = DateTime(2026, 1, 1)
    price = 50.0
    qty = -2.0
    commission = 1.0
    order = Order(oid!(acc), spot_inst, dt, price, qty)

    update_marks!(acc, pos_spot, dt, price, price, price)

    plan = Fastback.plan_fill(
        acc,
        pos_spot,
        order,
        dt,
        price,
        price,
        price,
        order.quantity,
        commission,
        0.0,
    )
    expected_cash_delta = to_settle(acc, spot_inst, -(qty * price * spot_inst.multiplier + commission))
    expected_init_margin = abs(qty) * price * spot_inst.multiplier * spot_inst.margin_init_short * usd_to_chf
    expected_maint_margin = abs(qty) * price * spot_inst.multiplier * spot_inst.margin_maint_short * usd_to_chf
    @test plan.cash_delta_settle ≈ expected_cash_delta atol=1e-10
    @test plan.new_init_margin_settle ≈ expected_init_margin atol=1e-10
    @test plan.new_maint_margin_settle ≈ expected_maint_margin atol=1e-10

    bal_before_open = acc.ledger.balances[chf_idx]
    trade = fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price)
    @test trade isa Trade
    @test acc.ledger.balances[chf_idx] ≈ bal_before_open + expected_cash_delta atol=1e-10
    @test acc.ledger.init_margin_used[margin_idx] ≈ expected_init_margin atol=1e-10

    accrue_borrow_fees!(acc, dt) # initialize clock
    bal_before_fee = acc.ledger.balances[chf_idx]
    dt_fee = dt + Day(1)
    accrue_borrow_fees!(acc, dt_fee)
    bal_after_fee = acc.ledger.balances[chf_idx]
    yearfrac = Dates.value(Dates.Millisecond(dt_fee - dt)) / (1000 * 60 * 60 * 24 * 365.0)
    expected_fee_settle = abs(qty) * price * spot_inst.multiplier * spot_inst.short_borrow_rate * yearfrac * usd_to_chf
    @test bal_before_fee - bal_after_fee ≈ expected_fee_settle atol=1e-8
    cf_fee = acc.cashflows[end]
    @test cf_fee.kind == CashflowKind.BorrowFee
    @test cf_fee.cash_index == chf_idx
    @test cf_fee.amount ≈ -expected_fee_settle atol=1e-8

    perp_inst = register_instrument!(acc, Instrument(
        Symbol("PERP/USDCHF"),
        :PERP,
        :USD;
        settle_symbol=:CHF,
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        multiplier=1.0,
    ))
    dt_perp = dt + Day(2)
    order_perp = Order(oid!(acc), perp_inst, dt_perp, 120.0, 1.0)
    trade_perp = fill_order!(acc, order_perp; dt=dt_perp, fill_price=order_perp.price, bid=order_perp.price, ask=order_perp.price, last=order_perp.price)
    @test trade_perp isa Trade

    bal_before_funding = acc.ledger.balances[chf_idx]
    funding_rate = 0.02
    apply_funding!(acc, perp_inst, dt_perp + Hour(8); funding_rate=funding_rate)
    payment_quote = -order_perp.quantity * order_perp.price * perp_inst.multiplier * funding_rate
    expected_payment_settle = payment_quote * usd_to_chf
    @test acc.ledger.balances[chf_idx] ≈ bal_before_funding + expected_payment_settle atol=1e-8
    cf_funding = acc.cashflows[end]
    @test cf_funding.kind == CashflowKind.Funding
    @test cf_funding.cash_index == chf_idx
    @test cf_funding.amount ≈ expected_payment_settle atol=1e-8
end

@testitem "FX financing lands in settlement cash with borrow fee + interest" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(
        ;
        broker=FlatFeeBroker(; borrow_by_cash=Dict(:CHF=>0.05), lend_by_cash=Dict(:CHF=>0.02)),
        funding=AccountFunding.Margined,
        base_currency=base_currency,
        margin_aggregation=MarginAggregation.BaseCurrency,
        exchange_rates=er,
    )

    deposit!(acc, :USD, 50_000.0)
    register_cash_asset!(acc, CashSpec(:CHF))
    deposit!(acc, :CHF, 1_000.0)

    usd_to_chf = 0.8
    update_rate!(er, cash_asset(acc, :USD), cash_asset(acc, :CHF), usd_to_chf)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOTFXI/USDCHF"),
        :SPOTFXI,
        :USD;
        settle_symbol=:CHF,
        settlement=SettlementStyle.PrincipalExchange,
        contract_kind=ContractKind.Spot,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.25,
        margin_init_short=0.5,
        margin_maint_short=0.25,
        short_borrow_rate=0.10,
        multiplier=1.0,
    ))

    dt0 = DateTime(2026, 1, 1)
    price = 100.0
    qty = -10.0

    trade = fill_order!(acc, Order(oid!(acc), inst, dt0, price, qty); dt=dt0, fill_price=price, bid=price, ask=price, last=price)
    @test trade isa Trade

    chf_idx = inst.settle_cash_index
    bal_before = acc.ledger.balances[chf_idx]
    eq_before = acc.ledger.equities[chf_idx]

    accrue_interest!(acc, dt0)
    accrue_borrow_fees!(acc, dt0)
    @test isempty(acc.cashflows)

    dt1 = dt0 + Day(1)
    advance_time!(acc, dt1; accrue_interest=true, accrue_borrow_fees=true)

    yearfrac = Dates.value(Dates.Millisecond(dt1 - dt0)) / (1000 * 60 * 60 * 24 * 365.0)
    short_proceeds_settle = abs(qty) * price * inst.multiplier * usd_to_chf
    expected_interest = (bal_before - short_proceeds_settle) * 0.02 * yearfrac
    expected_fee_settle = short_proceeds_settle * inst.short_borrow_rate * yearfrac
    expected_net = expected_interest - expected_fee_settle

    @test acc.ledger.balances[chf_idx] ≈ bal_before + expected_net atol=1e-8
    @test acc.ledger.equities[chf_idx] ≈ eq_before + expected_net atol=1e-8

    @test length(acc.cashflows) == 2
    interest_cf, fee_cf = acc.cashflows
    @test interest_cf.kind == CashflowKind.LendInterest
    @test interest_cf.cash_index == chf_idx
    @test interest_cf.amount ≈ expected_interest atol=1e-8

    @test fee_cf.kind == CashflowKind.BorrowFee
    @test fee_cf.cash_index == chf_idx
    @test fee_cf.inst_index == inst.index
    @test fee_cf.amount ≈ -expected_fee_settle atol=1e-8
end
