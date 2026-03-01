using Dates
using TestItemRunner

@testitem "Contract matrix: validate_instrument combinations" begin
    using Test, Fastback, Dates

    zero_dt = DateTime(0)
    expiry_dt = DateTime(2026, 1, 1)

    valid_cases = [
        ("spot cash settlement", InstrumentSpec(Symbol("SPOT/CASH"), :SPOT, :USD;
            contract_kind=ContractKind.Spot,
            settlement=SettlementStyle.PrincipalExchange,
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
            expiry=zero_dt,
        )),
        ("perpetual variation margin", InstrumentSpec(Symbol("PERP/VM"), :PERP, :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.VariationMargin,
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
            expiry=zero_dt,
        )),
        ("future with expiry", InstrumentSpec(Symbol("FUT/VM"), :FUT, :USD;
            contract_kind=ContractKind.Future,
            settlement=SettlementStyle.VariationMargin,
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
            expiry=expiry_dt,
        )),
    ]

    for (name, inst) in valid_cases
        @testset "$name" begin
            @test Fastback.validate_instrument_spec(inst) === nothing
        end
    end

    invalid_cases = [
        ("spot variation margin disallowed", InstrumentSpec(Symbol("SPOT/VM"), :SPOT, :USD;
            contract_kind=ContractKind.Spot,
            settlement=SettlementStyle.VariationMargin,
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
        )),
        ("perpetual cannot expire", InstrumentSpec(Symbol("PERP/EXP"), :PERP, :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.VariationMargin,
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
            expiry=expiry_dt,
        )),
        ("perpetual requires variation margin", InstrumentSpec(Symbol("PERP/CASH"), :PERP, :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.PrincipalExchange,
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
        )),
        ("future requires expiry", InstrumentSpec(Symbol("FUT/NOEXP"), :FUT, :USD;
            contract_kind=ContractKind.Future,
            settlement=SettlementStyle.VariationMargin,
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
        )),
        ("future requires variation margin", InstrumentSpec(Symbol("FUT/CASH"), :FUT, :USD;
            contract_kind=ContractKind.Future,
            settlement=SettlementStyle.PrincipalExchange,
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
            expiry=expiry_dt,
        )),
    ]

    for (name, inst) in invalid_cases
        @testset "$name" begin
            @test_throws ArgumentError Fastback.validate_instrument_spec(inst)
        end
    end
end

@testitem "Contract matrix: lifecycle helpers" begin
    using Test, Fastback, Dates

    now_dt = DateTime(2026, 1, 1)

    spot = InstrumentSpec(Symbol("SPOT/LIFE"), :SPOT, :USD;
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        expiry=DateTime(0),
    )
    spot_inst = Instrument(1, 1, 1, 1, spot)
    @test is_active(spot_inst, now_dt)
    @test !is_expired(spot_inst, now_dt)
    @test ensure_active(spot_inst, now_dt) === spot_inst

    perp_start = DateTime(2026, 2, 1)
    perp = InstrumentSpec(Symbol("PERP/LIFE"), :PERP, :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        start_time=perp_start,
        expiry=DateTime(0),
    )
    perp_inst = Instrument(2, 1, 1, 1, perp)
    @test !is_active(perp_inst, perp_start - Day(1))
    @test_throws ArgumentError ensure_active(perp_inst, perp_start - Day(1))
    @test is_active(perp_inst, perp_start)
    @test ensure_active(perp_inst, perp_start) === perp_inst
    @test !is_expired(perp_inst, perp_start + Day(10))

    fut_start = DateTime(2026, 3, 1)
    fut_expiry = DateTime(2026, 3, 15)
    future = InstrumentSpec(Symbol("FUT/LIFE"), :FUT, :USD;
        contract_kind=ContractKind.Future,
        settlement=SettlementStyle.VariationMargin,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        start_time=fut_start,
        expiry=fut_expiry,
    )
    future_inst = Instrument(3, 1, 1, 1, future)

    @test !is_active(future_inst, fut_start - Day(1))
    @test_throws ArgumentError ensure_active(future_inst, fut_start - Day(1))
    @test is_active(future_inst, fut_start)
    @test is_active(future_inst, fut_expiry - Day(1))
    @test is_expired(future_inst, fut_expiry)
    @test !is_active(future_inst, fut_expiry)
    @test_throws ArgumentError ensure_active(future_inst, fut_expiry)
end
