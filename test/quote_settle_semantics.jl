using TestItemRunner

@testitem "Quote/settle invariants and equity conversion" begin
    using Test, Fastback, Dates

    er = SpotExchangeRates()
    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency, margining_style=MarginingStyle.BaseCurrency, exchange_rates=er)

    add_asset!(er, cash_asset(acc.ledger, :USD))
    deposit!(acc, :USD, 10_000.0)
    register_cash_asset!(acc.ledger, :EUR)
    add_asset!(er, cash_asset(acc.ledger, :EUR))
    deposit!(acc, :EUR, 0.0)

    # 1 EUR = 1.2 USD
    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.2)

    inst = register_instrument!(acc, Instrument(
        Symbol("TEST/EURUSD"),
        :TEST,
        :EUR;
        settle_symbol=:USD,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.0,
        margin_init_short=0.0,
        margin_maint_long=0.0,
        margin_maint_short=0.0,
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
    trade = fill_order!(acc, order; dt=dt, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)
    @test trade isa Trade

    eq_before = acc.ledger.equities[inst.settle_cash_index]
    update_marks!(acc, inst, dt + Day(1), 60.0, 60.0, 60.0)
    eq_after = acc.ledger.equities[inst.settle_cash_index]

    expected_delta_settle = (10.0 * (60.0 - 50.0)) * 1.2
    @test eq_after - eq_before ≈ expected_delta_settle atol = 1e-10
end
