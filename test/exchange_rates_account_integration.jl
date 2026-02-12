using TestItemRunner

@testitem "Account stores exchange rates provider" begin
    using Test, Fastback

    er = SpotExchangeRates()
    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; exchange_rates=er, ledger=ledger, base_currency=base_currency)
    add_asset!(er, cash_asset(acc.ledger, :USD))

    deposit!(acc, :USD, 1.0)

    @test get_rate(er, cash_asset(acc.ledger, :USD), cash_asset(acc.ledger, :USD)) == 1.0
end
