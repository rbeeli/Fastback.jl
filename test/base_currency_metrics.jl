using TestItemRunner

@testitem "Base currency metrics" begin
    using Test, Fastback

    er = SpotExchangeRates()
    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, exchange_rates=er, ledger=ledger, base_currency=base_currency)

    add_asset!(er, cash_asset(acc.ledger, :USD))
    deposit!(acc, :USD, 1_000.0)
    register_cash_asset!(acc.ledger, :EUR)
    add_asset!(er, cash_asset(acc.ledger, :EUR))
    deposit!(acc, :EUR, 1_000.0)

    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.07)

    expected = 1_000.0 + 1_000.0 * 1.07
    @test equity_base_ccy(acc) ≈ expected
    @test balance_base_ccy(acc) ≈ expected
end
