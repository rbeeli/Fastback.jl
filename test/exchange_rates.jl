using TestItemRunner

@testitem "Spot exchange rates update via cash handles" begin
    using Test, Fastback

    base_currency=CashSpec(:USD)
    acc = Account(; base_currency=base_currency)
    usd = cash_asset(acc, :USD)
    eur = register_cash_asset!(acc, CashSpec(:EUR))

    er = ExchangeRates()

    update_rate!(er, eur, usd, 1.07)

    @test get_rate(er, eur, usd) == 1.07
    @test get_rate(er, usd, eur) ≈ 1 / 1.07
    @test get_rate(er, usd, usd) == 1.0
    @test get_rate(er, eur, eur) == 1.0
end

@testitem "Spot exchange rates same-currency lookup is identity" begin
    using Test, Fastback

    er = ExchangeRates()
    acc = Account(; base_currency=CashSpec(:NOK))
    nok = cash_asset(acc, :NOK)

    @test get_rate(er, nok, nok) == 1.0
end

@testitem "Account and exchange-rate overloads support cash and index fast paths" begin
    using Test, Fastback

    er = ExchangeRates()
    acc = Account(; base_currency=CashSpec(:USD), exchange_rates=er)
    usd = cash_asset(acc, :USD)
    eur = register_cash_asset!(acc, CashSpec(:EUR))

    update_rate!(er, eur.index, usd.index, 1.07)
    @test get_rate(er, eur.index, usd.index) == 1.07
    @test get_rate(er, usd.index, eur.index) ≈ 1 / 1.07

    update_rate!(acc, eur, usd, 1.10)
    @test get_rate(acc, eur, usd) == 1.10
    @test get_rate(acc, eur.index, usd.index) == 1.10

    update_rate!(acc, :EUR, :USD, 1.12)
    @test get_rate(acc, :EUR, :USD) == 1.12
    @test get_rate(acc, eur, usd) == 1.12
    @test get_rate(acc, eur.index, usd.index) == 1.12
end
