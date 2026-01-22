using Dates
using TestItemRunner

@testitem "Instrument contract kinds and lifecycle" begin
    using Test, Fastback, Dates

    # Defaults to spot with open-ended lifecycle
    spot = Instrument(Symbol("SPOT/USD"), :SPOT, :USD)
    @test spot.contract_kind == ContractKind.Spot
    @test spot.start_time == DateTime(0)
    @test spot.expiry == DateTime(0)
    @test !has_expiry(spot)
    @test is_active(spot, DateTime(2026, 1, 1))
    @test !is_expired(spot, DateTime(2026, 1, 1))

    # Expiring future between start_time and expiry
    start_dt = DateTime(2026, 2, 1)
    expiry_dt = DateTime(2026, 6, 1)
    future = Instrument(
        Symbol("FUT/USD"),
        :FUT,
        :USD;
        contract_kind=ContractKind.Future,
        start_time=start_dt,
        expiry=expiry_dt,
    )
    @test future.contract_kind == ContractKind.Future
    @test has_expiry(future)
    @test !is_active(future, start_dt - Day(1))
    @test is_active(future, start_dt)
    @test is_active(future, expiry_dt - Day(1))
    @test is_expired(future, expiry_dt)
    @test !is_active(future, expiry_dt + Day(1))

    # Perpetual with date-based time type and delayed activation
    start_date = Date(2026, 3, 15)
    perp = Instrument(
        Symbol("PERP/USD"),
        :PERP,
        :USD;
        contract_kind=ContractKind.Perpetual,
        time_type=Date,
        start_time=start_date,
    )
    @test perp.contract_kind == ContractKind.Perpetual
    @test perp.start_time == start_date
    @test perp.expiry == Date(0)
    @test !has_expiry(perp)
    @test !is_active(perp, start_date - Day(1))
    @test is_active(perp, start_date)
end
