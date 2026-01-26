using Dates
using TestItemRunner

@testitem "Instrument helper constructors return validated instruments" begin
    using Test, Fastback, Dates

    spot = spot_instrument(Symbol("SPOT/PHYS"), :SPOT, :USD)
    @test Fastback.validate_instrument(spot) === nothing
    @test spot.contract_kind == ContractKind.Spot
    @test spot.settlement == SettlementStyle.Asset
    @test spot.delivery_style == DeliveryStyle.PhysicalDeliver
    @test spot.margin_mode == MarginMode.None
    @test spot.expiry == DateTime(0)

    mspot = margin_spot_instrument(Symbol("SPOT/MGN"), :SPOT, :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    )
    @test Fastback.validate_instrument(mspot) === nothing
    @test is_margined_spot(mspot)

    perp = perpetual_instrument(Symbol("PERP/VM"), :PERP, :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    )
    @test Fastback.validate_instrument(perp) === nothing
    @test perp.contract_kind == ContractKind.Perpetual
    @test perp.settlement == SettlementStyle.VariationMargin
    @test perp.delivery_style == DeliveryStyle.CashSettle
    @test perp.expiry == DateTime(0)

    fut = future_instrument(Symbol("FUT/VM"), :FUT, :USD;
        expiry=DateTime(2026, 12, 31),
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    )
    @test Fastback.validate_instrument(fut) === nothing
    @test fut.contract_kind == ContractKind.Future
    @test fut.settlement == SettlementStyle.VariationMargin
    @test has_expiry(fut)
end

@testitem "Instrument constructor helpers reject invalid combinations" begin
    using Test, Fastback, Dates

    @test_throws ArgumentError margin_spot_instrument(Symbol("SPOT/NONE"), :SPOT, :USD;
        margin_mode=MarginMode.None,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    )

    @test_throws ArgumentError future_instrument(Symbol("FUT/NOMRG"), :FUT, :USD;
        expiry=DateTime(2026, 1, 1),
        margin_mode=MarginMode.None,
        margin_init_long=0.0,
        margin_init_short=0.0,
        margin_maint_long=0.0,
        margin_maint_short=0.0,
    )

    # direct validation guards for legacy constructor usage
    spot_vm = Instrument(Symbol("SPOT/VM"), :SPOT, :USD;
        settlement=SettlementStyle.VariationMargin,
    )
    @test_throws ArgumentError Fastback.validate_instrument(spot_vm)

    perp_with_expiry = Instrument(Symbol("PERP/EXP"), :PERP, :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        expiry=DateTime(2027, 1, 1),
    )
    @test_throws ArgumentError Fastback.validate_instrument(perp_with_expiry)
end
