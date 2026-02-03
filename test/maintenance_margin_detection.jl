using TestItemRunner

@testitem "Maintenance margin breach is detected" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 500.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOT/USD"),
        :SPOT,
        :USD;
        settlement=SettlementStyle.Cash,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_maint_long=0.25,
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
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD, margining_style=MarginingStyle.PerCurrency, exchange_rates=er)

    usd = Cash(:USD)
    eur = Cash(:EUR)
    deposit!(acc, usd, 10_000.0)
    deposit!(acc, eur, 200.0)

    update_rate!(er, eur, usd, 1.1)

    inst_eur = register_instrument!(acc, Instrument(
        Symbol("PER/EUR"),
        :PER,
        :EUR;
        settle_symbol=:EUR,
        settlement=SettlementStyle.Cash,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.2,
        margin_init_short=0.2,
        margin_maint_long=0.5,
        margin_maint_short=0.5,
    ))

    dt = DateTime(2026, 1, 1)
    trade = fill_order!(acc, Order(oid!(acc), inst_eur, dt, 100.0, 5.0); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    @test trade isa Trade

    @test excess_liquidity(acc, :USD) > 0
    @test excess_liquidity(acc, :EUR) < 0
    @test is_under_maintenance(acc)
    @test Fastback.check_invariants(acc)
end
