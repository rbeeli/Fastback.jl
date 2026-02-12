using TestItemRunner

@testitem "Spot exchange rates update via cash handles" begin
    using Test, Fastback

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    eur = register_cash_asset!(acc.ledger, :EUR)

    er = SpotExchangeRates()
    add_asset!(er, usd)
    add_asset!(er, eur)

    update_rate!(er, eur, usd, 1.07)

    @test get_rate(er, eur, usd) == 1.07
    @test get_rate(er, usd, eur) ≈ 1 / 1.07
    @test get_rate(er, usd, usd) == 1.0
    @test get_rate(er, eur, eur) == 1.0
end

@testitem "Spot exchange rates reject duplicate cash symbols" begin
    using Test, Fastback

    er = SpotExchangeRates()
    ledger = CashLedger()
    nok = register_cash_asset!(ledger, :NOK)

    add_asset!(er, nok)
    @test get_rate(er, nok, nok) == 1.0
    @test_throws ArgumentError add_asset!(er, nok)
end
