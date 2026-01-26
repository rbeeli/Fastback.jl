using TestItemRunner

@testitem "Quote/settle invariants and equity conversion" begin
    using Test, Fastback, Dates

    er = SpotExchangeRates()
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD, margining_style=MarginingStyle.BaseCurrency, exchange_rates=er)

    usd = Cash(:USD)
    eur = Cash(:EUR)
    deposit!(acc, usd, 10_000.0)   # registers USD/base
    deposit!(acc, eur, 0.0)        # registers EUR/quote

    # 1 EUR = 1.2 USD
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.2)

    inst = register_instrument!(acc, Instrument(
        Symbol("TEST/EURUSD"),
        :TEST,
        :EUR;
        settle_symbol=:USD,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.None,
        multiplier=1.0,
    ))

    # Round-trip conversion should be lossless within tolerance
    amt_quote = 100.0
    amt_settle = to_settle(acc, inst, amt_quote)
    @test amt_settle ≈ 120.0 atol = 1e-12
    @test to_quote(acc, inst, amt_settle) ≈ amt_quote atol = 1e-12

    # Equity changes must reflect converted value deltas, not raw quote deltas
    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 50.0, 10.0)
    trade = fill_order!(acc, order, dt, order.price)
    @test trade isa Trade

    eq_before = acc.equities[inst.settle_cash_index]
    update_marks!(acc, inst; dt=dt + Day(1), bid=60.0, ask=60.0)
    eq_after = acc.equities[inst.settle_cash_index]

    expected_delta_settle = (10.0 * (60.0 - 50.0)) * 1.2
    @test eq_after - eq_before ≈ expected_delta_settle atol = 1e-10
end
