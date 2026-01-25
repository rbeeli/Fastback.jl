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

@testitem "Instrument can have settle_symbol != quote_symbol when cash assets exist" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    register_cash_asset!(acc, Cash(:USD))
    register_cash_asset!(acc, Cash(:EUR))

    inst = Instrument(Symbol("BTC/USD.EUR"), :BTC, :USD;
        settle_symbol=:EUR,
        margin_symbol=:EUR,
    )

    register_instrument!(acc, inst)

    @test inst.settle_symbol == :EUR
    @test inst.settle_cash_index == cash_asset(acc, inst.settle_symbol).index
    @test inst.margin_cash_index == cash_asset(acc, inst.margin_symbol).index
    @test inst.quote_cash_index == cash_asset(acc, inst.quote_symbol).index
end

@testitem "register_instrument! errors when settle_symbol cash not registered" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    register_cash_asset!(acc, Cash(:USD))

    inst = Instrument(Symbol("BTC/USD.EUR"), :BTC, :USD;
        settle_symbol=:EUR,
    )

    @test_throws ArgumentError register_instrument!(acc, inst)
end
