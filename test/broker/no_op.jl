using Dates
using TestItemRunner

@testitem "NoOpBroker defaults to zero commission and financing" begin
    using Test, Fastback, Dates

    broker = NoOpBroker()
    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=broker,
    )
    deposit!(acc, :USD, 100.0)
    usd = cash_asset(acc, :USD)
    inst = register_instrument!(acc, spot_instrument(:NOOPUSD, :NOOP, :USD))

    dt = DateTime(2025, 1, 1)
    cq_maker = broker_commission(broker, inst, dt, 1.0, 100.0; is_maker=true)
    cq_taker = broker_commission(broker, inst, dt, 1.0, 100.0; is_maker=false)
    @test cq_maker.fixed == 0.0
    @test cq_maker.pct == 0.0
    @test cq_taker.fixed == 0.0
    @test cq_taker.pct == 0.0

    borrow, lend = broker_interest_rates(broker, usd, dt, 100.0)
    @test borrow == 0.0
    @test lend == 0.0

    exclude_frac, rebate_rate = broker_short_proceeds_rates(broker, usd, dt)
    @test exclude_frac == 1.0
    @test rebate_rate == 0.0
end
