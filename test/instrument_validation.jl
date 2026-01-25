using Dates
using TestItemRunner

@testitem "Spot cannot use variation margin settlement" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 0.0)

    inst = Instrument(Symbol("SPOT/VM"), :SPOT, :USD;
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.VariationMargin,
    )

    @test_throws ArgumentError register_instrument!(acc, inst)
end

@testitem "Perpetual validations" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 0.0)

    bad_settle = Instrument(Symbol("PERP/BADSETTLE"), :PERP, :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.Cash,
        margin_mode=MarginMode.PercentNotional,
    )
    @test_throws ArgumentError register_instrument!(acc, bad_settle)

    bad_expiry = Instrument(Symbol("PERP/EXPIRY"), :PERP, :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        expiry=DateTime(2026, 1, 1),
    )
    @test_throws ArgumentError register_instrument!(acc, bad_expiry)

    bad_margin = Instrument(Symbol("PERP/NOMARGIN"), :PERP, :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
    )
    @test_throws ArgumentError register_instrument!(acc, bad_margin)

    good = Instrument(Symbol("PERP/OK"), :PERP, :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
    )
    register_instrument!(acc, good)
end

@testitem "Future validations" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 0.0)

    bad_settle = Instrument(Symbol("FUT/BADSETTLE"), :FUT, :USD;
        contract_kind=ContractKind.Future,
        settlement=SettlementStyle.Cash,
        margin_mode=MarginMode.PercentNotional,
        expiry=DateTime(2026, 1, 2),
    )
    @test_throws ArgumentError register_instrument!(acc, bad_settle)

    bad_expiry = Instrument(Symbol("FUT/NOEXP"), :FUT, :USD;
        contract_kind=ContractKind.Future,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
    )
    @test_throws ArgumentError register_instrument!(acc, bad_expiry)

    bad_margin = Instrument(Symbol("FUT/NOMARGIN"), :FUT, :USD;
        contract_kind=ContractKind.Future,
        settlement=SettlementStyle.VariationMargin,
        expiry=DateTime(2026, 1, 2),
    )
    @test_throws ArgumentError register_instrument!(acc, bad_margin)

    good = Instrument(Symbol("FUT/OK"), :FUT, :USD;
        contract_kind=ContractKind.Future,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        expiry=DateTime(2026, 1, 2),
    )
    register_instrument!(acc, good)
end
