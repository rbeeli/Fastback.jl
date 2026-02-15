using TestItemRunner

@testitem "Spot on margin long uses initial margin" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOTM/USD"),
        :SPOTM,
        :USD;
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.25,
        margin_init_short=0.5,
        margin_maint_short=0.25,
    ))
    @test is_margined_spot(inst)

    dt = DateTime(2025, 1, 1)
    price = 100.0
    qty = 200.0                # notional = 20_000

    trade = fill_order!(acc, Order(oid!(acc), inst, dt, price, qty); dt=dt, fill_price=price, bid=price, ask=price, last=price)
    @test trade isa Trade

    usd = cash_asset(acc, :USD)

    @test cash_balance(acc, usd) ≈ -10_000.0 atol=1e-8
    @test equity(acc, usd) ≈ 10_000.0 atol=1e-8
    @test init_margin_used(acc, usd) ≈ 10_000.0 atol=1e-8
    @test available_funds(acc, usd) ≈ 0.0 atol=1e-8
    @test maint_margin_used(acc, usd) ≈ 5_000.0 atol=1e-8
end

@testitem "Margin spot long accrues borrow interest" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(
        ;
        broker=FlatFeeBroker(; borrow_by_cash=Dict(:USD=>0.10), lend_by_cash=Dict(:USD=>0.0)),
        funding=AccountFunding.Margined,
        base_currency=base_currency,
    )
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOTML/USD"),
        :SPOTML,
        :USD;
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.25,
        margin_init_short=0.5,
        margin_maint_short=0.25,
    ))

    dt0 = DateTime(2026, 1, 1)
    price = 100.0
    qty = 200.0                # notional = 20_000

    trade = fill_order!(acc, Order(oid!(acc), inst, dt0, price, qty); dt=dt0, fill_price=price, bid=price, ask=price, last=price)
    @test trade isa Trade

    usd = cash_asset(acc, :USD)
    bal_before = cash_balance(acc, usd)
    eq_before = equity(acc, usd)

    @test bal_before ≈ -10_000.0 atol=1e-8
    @test eq_before ≈ 10_000.0 atol=1e-8

    accrue_interest!(acc, dt0) # initialize clock
    @test isempty(acc.cashflows)

    dt1 = dt0 + Day(1)
    accrue_interest!(acc, dt1)

    yearfrac = Dates.value(Dates.Millisecond(dt1 - dt0)) / (1000 * 60 * 60 * 24 * 365.0)
    expected_interest = bal_before * 0.10 * yearfrac

    @test cash_balance(acc, usd) ≈ bal_before + expected_interest atol=1e-8
    @test equity(acc, usd) ≈ eq_before + expected_interest atol=1e-8

    cf = only(acc.cashflows)
    @test cf.kind == CashflowKind.BorrowInterest
    @test cf.cash_index == cash_asset(acc, :USD).index
    @test cf.amount ≈ expected_interest atol=1e-8
    @test cf.inst_index == 0
end

@testitem "Spot on margin short keeps equity, accrues borrow fees" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOTMS/USD"),
        :SPOTMS,
        :USD;
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.25,
        margin_init_short=0.5,
        margin_maint_short=0.25,
        short_borrow_rate=0.10,
    ))

    dt0 = DateTime(2025, 1, 1)
    price = 100.0
    qty = -200.0               # notional = 20_000

    trade = fill_order!(acc, Order(oid!(acc), inst, dt0, price, qty); dt=dt0, fill_price=price, bid=price, ask=price, last=price)
    @test trade isa Trade

    usd = cash_asset(acc, :USD)
    usd_idx = cash_asset(acc, :USD).index

    # Equity should remain the original deposit after opening the short.
    # Cash increases from short proceeds and is offset by negative position value.
    @test cash_balance(acc, usd) ≈ 30_000.0 atol=1e-8
    @test get_position(acc, inst).value_quote ≈ -20_000.0 atol=1e-8
    @test equity(acc, usd) ≈ 10_000.0 atol=1e-8
    @test init_margin_used(acc, usd) ≈ 10_000.0 atol=1e-8

    # Start borrow-fee clock, then accrue one day
    accrue_borrow_fees!(acc, dt0)
    dt1 = dt0 + Day(1)
    accrue_borrow_fees!(acc, dt1)

    expected_fee = 20_000.0 * 0.10 / 365.0
    @test acc.ledger.balances[usd_idx] ≈ 30_000.0 - expected_fee atol=1e-6
    @test acc.ledger.equities[usd_idx] ≈ 10_000.0 - expected_fee atol=1e-6
    cf = only(acc.cashflows)
    @test cf.kind == CashflowKind.BorrowFee
    @test cf.cash_index == usd_idx
    @test cf.inst_index == inst.index
    @test cf.amount ≈ -expected_fee atol=1e-6
end

@testitem "Margin spot short accrues borrow fee and interest" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(
        ;
        broker=FlatFeeBroker(; borrow_by_cash=Dict(:USD=>0.05), lend_by_cash=Dict(:USD=>0.02)),
        funding=AccountFunding.Margined,
        base_currency=base_currency,
    )
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOTMSI/USD"),
        :SPOTMSI,
        :USD;
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.25,
        margin_init_short=0.5,
        margin_maint_short=0.25,
        short_borrow_rate=0.10,
    ))

    dt0 = DateTime(2026, 1, 1)
    price = 100.0
    qty = -200.0               # notional = 20_000

    trade = fill_order!(acc, Order(oid!(acc), inst, dt0, price, qty); dt=dt0, fill_price=price, bid=price, ask=price, last=price)
    @test trade isa Trade

    usd = cash_asset(acc, :USD)
    bal_before = cash_balance(acc, usd)
    eq_before = equity(acc, usd)

    @test bal_before ≈ 30_000.0 atol=1e-8
    @test eq_before ≈ 10_000.0 atol=1e-8

    accrue_interest!(acc, dt0) # prime clocks
    accrue_borrow_fees!(acc, dt0)
    @test isempty(acc.cashflows)

    dt1 = dt0 + Day(1)
    advance_time!(acc, dt1; accrue_interest=true, accrue_borrow_fees=true)

    yearfrac = Dates.value(Dates.Millisecond(dt1 - dt0)) / (1000 * 60 * 60 * 24 * 365.0)
    expected_interest = bal_before * 0.02 * yearfrac
    expected_fee = abs(qty) * price * inst.multiplier * inst.short_borrow_rate * yearfrac
    expected_delta = expected_interest - expected_fee

    @test cash_balance(acc, usd) ≈ bal_before + expected_delta atol=1e-6
    @test equity(acc, usd) ≈ eq_before + expected_delta atol=1e-6

    @test length(acc.cashflows) == 2
    interest_cf = acc.cashflows[1]
    fee_cf = acc.cashflows[2]

    @test interest_cf.kind == CashflowKind.LendInterest
    @test interest_cf.cash_index == cash_asset(acc, :USD).index
    @test interest_cf.amount ≈ expected_interest atol=1e-8

    @test fee_cf.kind == CashflowKind.BorrowFee
    @test fee_cf.cash_index == cash_asset(acc, :USD).index
    @test fee_cf.inst_index == inst.index
    @test fee_cf.amount ≈ -expected_fee atol=1e-8
end

@testitem "Fully funded account applies margin checks to spot" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.FullyFunded, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(acc, spot_instrument(Symbol("SPOTC/USD"), :SPOTC, :USD))

    dt = DateTime(2025, 1, 1)
    price = 50.0
    qty = 100.0
    trade = fill_order!(acc, Order(oid!(acc), inst, dt, price, qty); dt=dt, fill_price=price, bid=price, ask=price, last=price)
    @test trade isa Trade

    usd = cash_asset(acc, :USD)
    usd_idx = cash_asset(acc, :USD).index

    balance_after_buy = cash_balance(acc, usd)
    @test balance_after_buy ≈ 5_000.0 atol=1e-8
    pos = get_position(acc, inst)
    @test pos.value_quote ≈ 5_000.0 atol=1e-8
    @test equity(acc, usd) ≈ 10_000.0 atol=1e-8
    @test acc.ledger.init_margin_used[usd_idx] == 5_000.0
    @test acc.ledger.maint_margin_used[usd_idx] == 5_000.0

    short_order = Order(oid!(acc), inst, dt, price, -400.0)
    err = try
        fill_order!(acc, short_order; dt=dt, fill_price=price, bid=price, ask=price, last=price)
        nothing
    catch e
        e
    end
    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.ShortNotAllowed

    @test cash_balance(acc, usd) ≈ balance_after_buy atol=1e-8
    @test cash_balance(acc, usd) ≥ 0.0
    @test acc.ledger.init_margin_used[usd_idx] == 5_000.0
    @test acc.ledger.maint_margin_used[usd_idx] == 5_000.0
end

@testitem "Fully funded account spread does not create synthetic margin deficit" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.FullyFunded, base_currency=base_currency)
    deposit!(acc, :USD, 100.0)

    inst = register_instrument!(acc, spot_instrument(Symbol("SPREADC/USD"), :SPREADC, :USD))
    usd = cash_asset(acc, :USD)

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 100.0, 1.0)
    trade = fill_order!(acc, order; dt=dt, fill_price=100.0, bid=99.0, ask=100.0, last=100.0)
    @test trade isa Trade

    pos = get_position(acc, inst)
    @test cash_balance(acc, usd) ≈ 0.0 atol=1e-12
    @test pos.mark_price ≈ 99.0 atol=1e-12
    @test pos.last_price ≈ 100.0 atol=1e-12
    @test equity(acc, usd) ≈ 99.0 atol=1e-12
    @test init_margin_used(acc, usd) ≈ 99.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 99.0 atol=1e-12
    @test available_funds(acc, usd) ≈ 0.0 atol=1e-12
    @test excess_liquidity(acc, usd) ≈ 0.0 atol=1e-12
    @test !is_under_maintenance(acc)

    update_marks!(acc, inst, dt + Hour(1), 98.0, 99.0, 99.0)
    @test pos.mark_price ≈ 98.0 atol=1e-12
    @test pos.last_price ≈ 99.0 atol=1e-12
    @test equity(acc, usd) ≈ 98.0 atol=1e-12
    @test init_margin_used(acc, usd) ≈ 98.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 98.0 atol=1e-12
    @test available_funds(acc, usd) ≈ 0.0 atol=1e-12
    @test excess_liquidity(acc, usd) ≈ 0.0 atol=1e-12
    @test !is_under_maintenance(acc)
end

@testitem "Fully funded account disallows opening short exposure" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.FullyFunded, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(acc, spot_instrument(Symbol("SHORTC/USD"), :SHORTC, :USD))

    dt = DateTime(2026, 1, 1)
    price = 50.0
    order = Order(oid!(acc), inst, dt, price, -1.0)

    err = try
        fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price)
        nothing
    catch e
        e
    end
    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.ShortNotAllowed
end

@testitem "Fully funded account uses full notional margin" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.FullyFunded, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(
        acc,
        spot_instrument(
            Symbol("MARGINC/USD"),
            :MARGINC,
            :USD;
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.2,
            margin_init_short=0.2,
            margin_maint_long=0.1,
            margin_maint_short=0.1,
        ),
    )

    dt = DateTime(2026, 1, 1)
    price = 100.0

    oversized = Order(oid!(acc), inst, dt, price, 150.0)
    err = try
        fill_order!(acc, oversized; dt=dt, fill_price=price, bid=price, ask=price, last=price)
        nothing
    catch e
        e
    end
    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin

    ok_order = Order(oid!(acc), inst, dt, price, 100.0)
    trade = fill_order!(acc, ok_order; dt=dt, fill_price=price, bid=price, ask=price, last=price)
    @test trade isa Trade

    usd = cash_asset(acc, :USD)
    @test cash_balance(acc, usd) ≈ 0.0 atol=1e-8
    @test acc.ledger.init_margin_used[cash_asset(acc, :USD).index] ≈ 10_000.0 atol=1e-8
    @test acc.ledger.maint_margin_used[cash_asset(acc, :USD).index] ≈ 10_000.0 atol=1e-8
end

@testitem "Spot mark move converts quote P&L into settlement equity" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:CHF)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency, margin_aggregation=MarginAggregation.BaseCurrency, exchange_rates=er)

    chf = cash_asset(acc, :CHF)
    deposit!(acc, :CHF, 10_000.0)
    eur = register_cash_asset!(acc, CashSpec(:EUR))
    deposit!(acc, :EUR, 0.0) # register quote currency

    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :CHF), 1.1)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOTFX/EURCHF"),
        :SPOTFX,
        :EUR;
        settle_symbol=:CHF,
        settlement=SettlementStyle.PrincipalExchange,
        contract_kind=ContractKind.Spot,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.25,
        margin_init_short=0.5,
        margin_maint_short=0.25,
        multiplier=1.0,
    ))

    dt = DateTime(2026, 1, 1)
    price_entry = 100.0
    qty = 10.0

    trade = fill_order!(acc, Order(oid!(acc), inst, dt, price_entry, qty); dt=dt, fill_price=price_entry, bid=price_entry, ask=price_entry, last=price_entry)
    @test trade isa Trade

    equity_before = equity(acc, chf)
    price_mark = 110.0
    update_marks!(acc, inst, dt + Hour(1), price_mark, price_mark, price_mark)

    pos = get_position(acc, inst)
    expected_pnl_quote = qty * (price_mark - price_entry) * inst.multiplier
    @test pos.pnl_quote ≈ expected_pnl_quote atol=1e-8

    rate = get_rate(acc.exchange_rates, cash_asset(acc, :EUR), cash_asset(acc, :CHF))
    @test rate ≈ 1.1 atol=1e-12
    equity_after = equity(acc, chf)
    @test equity_after - equity_before ≈ expected_pnl_quote * rate atol=1e-8
end
