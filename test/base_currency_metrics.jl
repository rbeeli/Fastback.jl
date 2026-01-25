using TestItemRunner

@testitem "Base currency metrics" begin
    using Test, Fastback

    er = SpotExchangeRates()
    acc = Account(; mode=AccountMode.Margin, exchange_rates=er, base_currency=:USD)

    deposit!(acc, Cash(:USD), 1_000.0)
    deposit!(acc, Cash(:EUR), 1_000.0)

    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.07)

    expected = 1_000.0 + 1_000.0 * 1.07
    @test equity_base_ccy(acc) ≈ expected
    @test balance_base_ccy(acc) ≈ expected
end
