using Dates
using TestItemRunner

@testitem "Contract matrix: validate_instrument combinations" begin
    using Test, Fastback, Dates

    zero_dt = DateTime(0)
    expiry_dt = DateTime(2026, 1, 1)

    valid_cases = [
        ("spot asset settlement", Instrument(Symbol("SPOT/ASSET"), :SPOT, :USD;
            contract_kind=ContractKind.Spot,
            settlement=SettlementStyle.Asset,
            expiry=zero_dt,
        )),
        ("perpetual variation margin", Instrument(Symbol("PERP/VM"), :PERP, :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            expiry=zero_dt,
        )),
        ("future with expiry", Instrument(Symbol("FUT/VM"), :FUT, :USD;
            contract_kind=ContractKind.Future,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            expiry=expiry_dt,
        )),
    ]

    for (name, inst) in valid_cases
        @testset "$name" begin
            @test Fastback.validate_instrument(inst) === nothing
        end
    end

    invalid_cases = [
        ("spot variation margin disallowed", Instrument(Symbol("SPOT/VM"), :SPOT, :USD;
            contract_kind=ContractKind.Spot,
            settlement=SettlementStyle.VariationMargin,
        )),
        ("perpetual cannot expire", Instrument(Symbol("PERP/EXP"), :PERP, :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            expiry=expiry_dt,
        )),
        ("perpetual requires variation margin", Instrument(Symbol("PERP/ASSET"), :PERP, :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.Asset,
            margin_mode=MarginMode.PercentNotional,
        )),
        ("future requires expiry", Instrument(Symbol("FUT/NOEXP"), :FUT, :USD;
            contract_kind=ContractKind.Future,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
        )),
        ("future requires variation margin", Instrument(Symbol("FUT/CASH"), :FUT, :USD;
            contract_kind=ContractKind.Future,
            settlement=SettlementStyle.Cash,
            margin_mode=MarginMode.PercentNotional,
            expiry=expiry_dt,
        )),
    ]

    for (name, inst) in invalid_cases
        @testset "$name" begin
            @test_throws ArgumentError Fastback.validate_instrument(inst)
        end
    end
end

@testitem "Contract matrix: lifecycle helpers" begin
    using Test, Fastback, Dates

    now_dt = DateTime(2026, 1, 1)

    spot = Instrument(Symbol("SPOT/LIFE"), :SPOT, :USD;
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.Asset,
        expiry=DateTime(0),
    )
    @test is_active(spot, now_dt)
    @test !is_expired(spot, now_dt)
    @test ensure_active(spot, now_dt) === spot

    perp_start = DateTime(2026, 2, 1)
    perp = Instrument(Symbol("PERP/LIFE"), :PERP, :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        start_time=perp_start,
        expiry=DateTime(0),
    )
    @test !is_active(perp, perp_start - Day(1))
    @test_throws ArgumentError ensure_active(perp, perp_start - Day(1))
    @test is_active(perp, perp_start)
    @test ensure_active(perp, perp_start) === perp
    @test !is_expired(perp, perp_start + Day(10))

    fut_start = DateTime(2026, 3, 1)
    fut_expiry = DateTime(2026, 3, 15)
    future = Instrument(Symbol("FUT/LIFE"), :FUT, :USD;
        contract_kind=ContractKind.Future,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        start_time=fut_start,
        expiry=fut_expiry,
    )

    @test !is_active(future, fut_start - Day(1))
    @test_throws ArgumentError ensure_active(future, fut_start - Day(1))
    @test is_active(future, fut_start)
    @test is_active(future, fut_expiry - Day(1))
    @test is_expired(future, fut_expiry)
    @test !is_active(future, fut_expiry)
    @test_throws ArgumentError ensure_active(future, fut_expiry)
end
