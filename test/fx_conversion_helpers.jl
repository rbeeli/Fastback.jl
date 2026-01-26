using TestItemRunner

@testitem "FX conversions centralize quote→settle→base flows" begin
    using Test, Fastback, Dates

    er = SpotExchangeRates()
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD, margining_style=MarginingStyle.BaseCurrency, exchange_rates=er)

    usd = Cash(:USD)
    chf = Cash(:CHF)
    deposit!(acc, usd, 50_000.0)
    deposit!(acc, chf, 0.0) # register CHF

    usd_to_chf = 0.9
    update_rate!(er, cash_asset(acc, :USD), cash_asset(acc, :CHF), usd_to_chf)

    spot_inst = register_instrument!(acc, Instrument(
        Symbol("SPOT/USDCHF"),
        :SPOT,
        :USD;
        settle_symbol=:CHF,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.2,
        margin_init_short=0.2,
        margin_maint_long=0.1,
        margin_maint_short=0.1,
        short_borrow_rate=0.1,
        multiplier=1.0,
    ))
    pos_spot = get_position(acc, spot_inst)
    chf_idx = spot_inst.settle_cash_index

    dt = DateTime(2026, 1, 1)
    price = 50.0
    qty = -2.0
    commission = 1.0
    order = Order(oid!(acc), spot_inst, dt, price, qty)

    update_marks!(acc, pos_spot; dt=dt, close_price=price)

    plan = plan_fill(acc, pos_spot, order, dt, price; commission=commission)
    expected_cash_delta = (-(price * qty * spot_inst.multiplier) - commission) * usd_to_chf
    expected_init_margin = abs(qty) * price * spot_inst.multiplier * spot_inst.margin_init_short * usd_to_chf
    expected_maint_margin = abs(qty) * price * spot_inst.multiplier * spot_inst.margin_maint_short * usd_to_chf
    @test plan.cash_delta ≈ expected_cash_delta atol=1e-10
    @test plan.new_init_margin_settle ≈ expected_init_margin atol=1e-10
    @test plan.new_maint_margin_settle ≈ expected_maint_margin atol=1e-10

    trade = fill_order!(acc, order, dt, price; commission=commission)
    @test trade isa Trade
    @test acc.balances[chf_idx] ≈ expected_cash_delta atol=1e-10
    @test acc.init_margin_used[chf_idx] ≈ expected_init_margin atol=1e-10

    accrue_borrow_fees!(acc, dt) # initialize clock
    bal_before_fee = acc.balances[chf_idx]
    dt_fee = dt + Day(1)
    accrue_borrow_fees!(acc, dt_fee)
    bal_after_fee = acc.balances[chf_idx]
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
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        multiplier=1.0,
    ))
    dt_perp = dt + Day(2)
    order_perp = Order(oid!(acc), perp_inst, dt_perp, 120.0, 1.0)
    trade_perp = fill_order!(acc, order_perp, dt_perp, order_perp.price)
    @test trade_perp isa Trade

    bal_before_funding = acc.balances[chf_idx]
    funding_rate = 0.02
    apply_funding!(acc, perp_inst, dt_perp + Hour(8); funding_rate=funding_rate, mark_price=order_perp.price)
    payment_quote = -order_perp.quantity * order_perp.price * perp_inst.multiplier * funding_rate
    expected_payment_settle = payment_quote * usd_to_chf
    @test acc.balances[chf_idx] ≈ bal_before_funding + expected_payment_settle atol=1e-8
    cf_funding = acc.cashflows[end]
    @test cf_funding.kind == CashflowKind.Funding
    @test cf_funding.cash_index == chf_idx
    @test cf_funding.amount ≈ expected_payment_settle atol=1e-8
end
