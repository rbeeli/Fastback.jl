using TestItemRunner

@testitem "Account defaults to ExchangeRates and same-currency rate is identity" begin
    using Test, Fastback

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; ledger=ledger, base_currency=base_currency)

    deposit!(acc, :USD, 1.0)

    @test acc.exchange_rates isa ExchangeRates
    @test get_rate(acc.exchange_rates, cash_asset(acc.ledger, :USD), cash_asset(acc.ledger, :USD)) == 1.0
end
