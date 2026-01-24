using Dates
using TestItemRunner

@testitem "Accrues lend interest on positive balance" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin)
    usd = Cash(:USD)
    deposit!(acc, usd, 1_000.0)
    set_interest_rates!(acc, :USD; borrow=0.10, lend=0.05)

    start_dt = DateTime(2026, 1, 1)
    accrue_interest!(acc, start_dt) # initialize accrual clock
    accrue_interest!(acc, start_dt + Day(365))

    @test cash_balance(acc, usd) ≈ 1_050.0 atol=1e-8
    @test equity(acc, usd) ≈ cash_balance(acc, usd) atol=1e-8
end

@testitem "Accrues borrow interest on negative balance" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin)
    usd = Cash(:USD)

    withdraw!(acc, usd, 1_000.0) # creates and registers USD with negative balance
    set_interest_rates!(acc, :USD; borrow=0.10, lend=0.05)

    start_dt = DateTime(2026, 1, 1)
    accrue_interest!(acc, start_dt) # initialize accrual clock
    accrue_interest!(acc, start_dt + Day(365))

    @test cash_balance(acc, usd) ≈ -1_100.0 atol=1e-8
    @test equity(acc, usd) ≈ cash_balance(acc, usd) atol=1e-8
end
