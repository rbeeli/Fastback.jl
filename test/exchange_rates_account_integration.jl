using TestItemRunner

@testitem "Account defaults to ExchangeRates and same-currency rate is identity" begin
    using Test, Fastback

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), base_currency=base_currency)

    deposit!(acc, :USD, 1.0)

    @test acc.exchange_rates isa ExchangeRates
    @test get_rate(acc.exchange_rates, cash_asset(acc, :USD), cash_asset(acc, :USD)) == 1.0
end
