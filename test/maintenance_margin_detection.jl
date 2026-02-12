using TestItemRunner

@testitem "Maintenance margin breach is detected" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    deposit!(acc, :USD, 500.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOT/USD"),
        :SPOT,
        :USD;
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))

    dt = DateTime(2024, 1, 1)
    price = 100.0
    qty = 10.0

    trade = fill_order!(acc, Order(oid!(acc), inst, dt, price, qty); dt=dt, fill_price=price, bid=price, ask=price, last=price)
    @test trade isa Trade

    # Mark price down to trigger maintenance breach: PnL = (20-100)*10 = -800, equity = 200 < maint 250
    update_marks!(acc, inst, dt, 20.0, 20.0, 20.0)

    @test is_under_maintenance(acc) == true
    @test maint_deficit_base_ccy(acc) > 0
end

@testitem "Per-currency maintenance breach is detected" begin
    using Test, Fastback, Dates

    er = SpotExchangeRates()
    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency, margining_style=MarginingStyle.PerCurrency, exchange_rates=er)

    add_asset!(er, cash_asset(acc.ledger, :USD))
    deposit!(acc, :USD, 10_000.0)
    register_cash_asset!(acc.ledger, :EUR)
    add_asset!(er, cash_asset(acc.ledger, :EUR))
    deposit!(acc, :EUR, 200.0)

    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.1)

    inst_eur = register_instrument!(acc, Instrument(
        Symbol("PER/EUR"),
        :PER,
        :EUR;
        settle_symbol=:EUR,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.3,
        margin_init_short=0.3,
        margin_maint_long=0.2,
        margin_maint_short=0.2,
    ))

    dt = DateTime(2026, 1, 1)
    trade = fill_order!(acc, Order(oid!(acc), inst_eur, dt, 100.0, 5.0); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    @test trade isa Trade

    # With valid margin schedule (init >= maint), a mark-down can still create
    # a per-currency maintenance deficit.
    update_marks!(acc, inst_eur, dt + Hour(1), 70.0, 70.0, 70.0)

    @test excess_liquidity(acc, cash_asset(acc.ledger, :USD)) > 0
    @test excess_liquidity(acc, cash_asset(acc.ledger, :EUR)) < 0
    @test is_under_maintenance(acc)
    @test Fastback.check_invariants(acc)
end
