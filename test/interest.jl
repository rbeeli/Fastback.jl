using Dates
using TestItemRunner

@testitem "Accrues lend interest on positive balance" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(
        ;
        broker=FlatFeeBroker(; borrow_by_cash=Dict(:USD=>0.10), lend_by_cash=Dict(:USD=>0.05)),
        mode=AccountMode.Margin,
        base_currency=base_currency,
    )
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000.0)

    start_dt = DateTime(2026, 1, 1)
    accrue_interest!(acc, start_dt) # initialize accrual clock
    @test isempty(acc.cashflows)

    bal_before = cash_balance(acc, usd)
    eq_before = equity(acc, usd)
    accrue_interest!(acc, start_dt + Day(365))

    expected_interest = 50.0
    @test cash_balance(acc, usd) ≈ bal_before + expected_interest atol=1e-8
    @test equity(acc, usd) ≈ eq_before + expected_interest atol=1e-8

    cf = only(acc.cashflows)
    @test cf.kind == CashflowKind.LendInterest
    @test cf.cash_index == cash_asset(acc, :USD).index
    @test cf.amount ≈ expected_interest atol=1e-8
    @test cf.inst_index == 0
    @test cash_balance(acc, usd) - bal_before ≈ sum(cf.amount for cf in acc.cashflows) atol=1e-8
end

@testitem "Accrues borrow interest on negative balance" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(
        ;
        broker=FlatFeeBroker(; borrow_by_cash=Dict(:USD=>0.10), lend_by_cash=Dict(:USD=>0.05)),
        mode=AccountMode.Margin,
        base_currency=base_currency,
    )
    usd = cash_asset(acc, :USD)

    deposit!(acc, :USD, 0.0) # register cash asset
    # Simulate negative balance that could arise from mark-to-market losses
    Fastback._adjust_cash_idx!(acc.ledger, cash_asset(acc, :USD).index, -1_000.0)

    start_dt = DateTime(2026, 1, 1)
    accrue_interest!(acc, start_dt) # initialize accrual clock
    @test isempty(acc.cashflows)

    bal_before = cash_balance(acc, usd)
    eq_before = equity(acc, usd)
    accrue_interest!(acc, start_dt + Day(365))

    expected_interest = -100.0
    @test cash_balance(acc, usd) ≈ bal_before + expected_interest atol=1e-8
    @test equity(acc, usd) ≈ eq_before + expected_interest atol=1e-8

    cf = only(acc.cashflows)
    @test cf.kind == CashflowKind.BorrowInterest
    @test cf.cash_index == cash_asset(acc, :USD).index
    @test cf.amount ≈ expected_interest atol=1e-8
    @test cf.inst_index == 0
    @test cash_balance(acc, usd) - bal_before ≈ sum(cf.amount for cf in acc.cashflows) atol=1e-8
end
