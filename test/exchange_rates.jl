using TestItemRunner

@testitem "Spot exchange rates use cash indexes" begin
    using Test, Fastback

    usd = Cash(:USD)
    eur = Cash(:EUR)

    acc = Account(; base_currency=:USD)
    register_cash_asset!(acc, usd)
    register_cash_asset!(acc, eur)

    er = SpotExchangeRates()
    add_asset!(er, usd)
    add_asset!(er, eur)

    update_rate!(er, eur, usd, 1.07)

    @test get_rate(er, eur, usd) == 1.07
    @test get_rate(er, usd, eur) ≈ 1 / 1.07
    @test get_rate(er, usd, usd) == 1.0
    @test get_rate(er, eur, eur) == 1.0
end

@testitem "Spot exchange rates reject unindexed cash" begin
    using Test, Fastback

    er = SpotExchangeRates()
    nok = Cash(:NOK)

    @test_throws ArgumentError add_asset!(er, nok)

    acc = Account(; base_currency=:USD)
    register_cash_asset!(acc, nok)

    add_asset!(er, nok)
    @test get_rate(er, nok, nok) == 1.0
end
