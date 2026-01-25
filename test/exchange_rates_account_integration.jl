using TestItemRunner

@testitem "Account stores exchange rates provider" begin
    using Test, Fastback

    er = SpotExchangeRates()
    acc = Account(; exchange_rates=er, base_currency=:USD)

    deposit!(acc, Cash(:USD), 1.0)

    @test get_rate(er, cash_asset(acc, :USD), cash_asset(acc, :USD)) == 1.0
end
