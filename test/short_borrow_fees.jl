using TestItemRunner

@testitem "short borrow fees accrue on principal-exchange spot shorts" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
    deposit!(acc, :USD, 5_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("SHORT/USD"), :SHORT, :USD;
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1, margin_init_short=0.1,
        margin_maint_long=0.05, margin_maint_short=0.05,
        short_borrow_rate=0.1))

    dt0 = DateTime(2025, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, -10.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    accrue_borrow_fees!(acc, dt0) # initialize clock
    @test isempty(acc.cashflows)

    before_bal = acc.ledger.balances[inst.quote_cash_index]
    dt1 = dt0 + Year(1)
    accrue_borrow_fees!(acc, dt1)
    after_bal = acc.ledger.balances[inst.quote_cash_index]

    fee = before_bal - after_bal
    @test fee ≈ 10 * 100.0 * 0.1 atol=1e-6
    @test get_position(acc, inst).quantity == -10.0

    cf = only(acc.cashflows)
    @test cf.kind == CashflowKind.BorrowFee
    @test cf.cash_index == inst.settle_cash_index
    @test cf.inst_index == inst.index
    @test cf.amount ≈ -fee atol=1e-6
    @test fee ≈ -cf.amount atol=1e-6
    @test after_bal - before_bal ≈ cf.amount atol=1e-6
end

@testitem "short borrow fees use last price, not liquidation mark" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
    deposit!(acc, :USD, 5_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("SHORTSPREAD/USD"), :SHORTSPREAD, :USD;
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1, margin_init_short=0.1,
        margin_maint_long=0.05, margin_maint_short=0.05,
        short_borrow_rate=0.1))

    dt0 = DateTime(2026, 1, 1)
    bid = 99.0
    ask = 101.0
    last = 100.0
    qty = -10.0

    fill_order!(acc, Order(oid!(acc), inst, dt0, last, qty); dt=dt0, fill_price=last, bid=bid, ask=ask, last=last)

    accrue_borrow_fees!(acc, dt0) # initialize clock
    before_bal = cash_balance(acc, cash_asset(acc, :USD))

    dt1 = dt0 + Day(1)
    accrue_borrow_fees!(acc, dt1)
    after_bal = cash_balance(acc, cash_asset(acc, :USD))

    yearfrac = Dates.value(Dates.Millisecond(dt1 - dt0)) / (1000 * 60 * 60 * 24 * 365.0)
    expected_fee = abs(qty) * last * inst.multiplier * inst.short_borrow_rate * yearfrac

    @test before_bal - after_bal ≈ expected_fee atol=1e-10
end

@testitem "short borrow fees use absolute price when market is negative" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 5_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("SHORTNEG/USD"), :SHORTNEG, :USD;
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1, margin_init_short=0.1,
        margin_maint_long=0.05, margin_maint_short=0.05,
        short_borrow_rate=0.1))

    dt0 = DateTime(2026, 1, 1)
    negative_price = -100.0
    qty = -10.0

    fill_order!(
        acc,
        Order(oid!(acc), inst, dt0, negative_price, qty);
        dt=dt0,
        fill_price=negative_price,
        bid=negative_price,
        ask=negative_price,
        last=negative_price,
    )

    accrue_borrow_fees!(acc, dt0) # initialize clock
    bal_before = cash_balance(acc, usd)
    dt1 = dt0 + Day(1)
    accrue_borrow_fees!(acc, dt1)
    bal_after = cash_balance(acc, usd)

    yearfrac = Dates.value(Dates.Millisecond(dt1 - dt0)) / (1000 * 60 * 60 * 24 * 365.0)
    expected_fee = abs(qty) * abs(negative_price) * inst.multiplier * inst.short_borrow_rate * yearfrac
    cf = acc.cashflows[end]

    @test bal_before - bal_after ≈ expected_fee atol=1e-10
    @test cf.kind == CashflowKind.BorrowFee
    @test cf.amount ≈ -expected_fee atol=1e-10
end

@testitem "borrow fees start at short open time" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("SHORTOPEN/USD"), :SHORTOPEN, :USD;
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1, margin_init_short=0.1,
        margin_maint_long=0.05, margin_maint_short=0.05,
        short_borrow_rate=0.2))

    dt0 = DateTime(2026, 1, 1)
    accrue_borrow_fees!(acc, dt0) # no positions yet
    @test isempty(acc.cashflows)

    dt1 = dt0 + Day(1)
    price = 100.0
    qty = -5.0
    fill_order!(acc, Order(oid!(acc), inst, dt1, price, qty); dt=dt1, fill_price=price, bid=price, ask=price, last=price)

    dt2 = dt1 + Day(1)
    accrue_borrow_fees!(acc, dt2)

    yearfrac = Dates.value(Dates.Millisecond(dt2 - dt1)) / (1000 * 60 * 60 * 24 * 365.0)
    expected_fee = abs(qty) * price * inst.multiplier * inst.short_borrow_rate * yearfrac

    borrow_cfs = filter(cf -> cf.kind == CashflowKind.BorrowFee, acc.cashflows)
    @test length(borrow_cfs) == 1
    @test only(borrow_cfs).amount ≈ -expected_fee atol=1e-10
end

@testitem "borrow fees stop at short close time" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("SHORTCLOSE/USD"), :SHORTCLOSE, :USD;
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1, margin_init_short=0.1,
        margin_maint_long=0.05, margin_maint_short=0.05,
        short_borrow_rate=0.2))

    dt0 = DateTime(2026, 1, 1)
    price = 100.0
    qty = -5.0
    fill_order!(acc, Order(oid!(acc), inst, dt0, price, qty); dt=dt0, fill_price=price, bid=price, ask=price, last=price)

    dt1 = dt0 + Day(1)
    fill_order!(acc, Order(oid!(acc), inst, dt1, price, -qty); dt=dt1, fill_price=price, bid=price, ask=price, last=price)

    yearfrac = Dates.value(Dates.Millisecond(dt1 - dt0)) / (1000 * 60 * 60 * 24 * 365.0)
    expected_fee = abs(qty) * price * inst.multiplier * inst.short_borrow_rate * yearfrac

    borrow_cfs = filter(cf -> cf.kind == CashflowKind.BorrowFee, acc.cashflows)
    @test length(borrow_cfs) == 1
    @test only(borrow_cfs).amount ≈ -expected_fee atol=1e-10

    dt2 = dt1 + Day(1)
    accrue_borrow_fees!(acc, dt2)

    borrow_cfs_after = filter(cf -> cf.kind == CashflowKind.BorrowFee, acc.cashflows)
    @test length(borrow_cfs_after) == 1
end
