using Dates
using TestItemRunner

@testitem "FlatFeeBroker commission and cash-rate maps" begin
    using Test, Fastback, Dates

    broker = FlatFeeBroker(;
        fixed=1.5,
        pct=0.001,
        borrow_by_cash=Dict(:USD=>0.08),
        lend_by_cash=Dict(:USD=>0.02),
        short_proceeds_exclusion_by_cash=Dict(:USD=>0.4),
        short_proceeds_rebate_by_cash=Dict(:USD=>0.01),
    )

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=broker,
    )
    register_cash_asset!(acc, CashSpec(:EUR))
    usd = cash_asset(acc, :USD)
    eur = cash_asset(acc, :EUR)
    inst = register_instrument!(acc, spot_instrument(:FLATUSD, :FLAT, :USD))

    dt = DateTime(2025, 1, 1)
    commission = broker_commission(broker, inst, dt, 2.0, 100.0; is_maker=true)
    @test commission.fixed == 1.5
    @test commission.pct == 0.001

    borrow_usd, lend_usd = broker_interest_rates(broker, usd, dt, 1_000.0)
    @test borrow_usd == 0.08
    @test lend_usd == 0.02

    borrow_eur, lend_eur = broker_interest_rates(broker, eur, dt, 1_000.0)
    @test borrow_eur == 0.0
    @test lend_eur == 0.0

    exclude_usd, rebate_usd = broker_short_proceeds_rates(broker, usd, dt)
    @test exclude_usd == 0.4
    @test rebate_usd == 0.01

    exclude_eur, rebate_eur = broker_short_proceeds_rates(broker, eur, dt)
    @test exclude_eur == 1.0
    @test rebate_eur == 0.0
end

@testitem "FlatFeeBroker validates short-proceeds exclusion range" begin
    using Test, Fastback

    @test_throws ArgumentError FlatFeeBroker(;
        short_proceeds_exclusion_by_cash=Dict(:USD=>-0.1),
    )
    @test_throws ArgumentError FlatFeeBroker(;
        short_proceeds_exclusion_by_cash=Dict(:USD=>1.1),
    )
    @test_throws ArgumentError FlatFeeBroker(;
        short_proceeds_exclusion_by_cash=Dict(:USD=>NaN),
    )
end
