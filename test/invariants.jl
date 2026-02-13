using Dates
using TestItemRunner

@testitem "Account reconciliation after sequence" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency, margining_style=MarginingStyle.BaseCurrency, exchange_rates=er)

    add_asset!(er, cash_asset(acc.ledger, :USD))
    deposit!(acc, :USD, 10_000.0)
    register_cash_asset!(acc.ledger, :EUR)
    add_asset!(er, cash_asset(acc.ledger, :EUR))
    deposit!(acc, :EUR, 5_000.0)

    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.1)

    set_interest_rates!(acc, :USD; borrow=0.0, lend=0.05)
    set_interest_rates!(acc, :EUR; borrow=0.0, lend=0.02)

    @test Fastback.check_invariants(acc)

    inst_asset = register_instrument!(acc, Instrument(
        Symbol("ASSET/EURUSD"),
        :ASSET,
        :EUR;
        settle_symbol=:USD,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.2,
        margin_init_short=0.2,
        margin_maint_long=0.1,
        margin_maint_short=0.1,
    ))

    inst_perp = register_instrument!(acc, perpetual_instrument(
        Symbol("PERP/USD"),
        :PERP,
        :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))

    @test Fastback.check_invariants(acc)

    dt0 = DateTime(2026, 1, 1)
    accrue_interest!(acc, dt0) # initialize accrual clock
    @test Fastback.check_invariants(acc)

    order_asset = Order(oid!(acc), inst_asset, dt0, 100.0, 2.0)
    trade_asset = fill_order!(acc, order_asset; dt=dt0, fill_price=order_asset.price, bid=order_asset.price, ask=order_asset.price, last=order_asset.price)
    @test trade_asset isa Trade
    @test Fastback.check_invariants(acc)

    update_marks!(acc, inst_asset, dt0 + Day(1), 120.0, 120.0, 120.0)
    @test Fastback.check_invariants(acc)

    order_perp = Order(oid!(acc), inst_perp, dt0 + Day(1), 50.0, 1.0)
    trade_perp = fill_order!(acc, order_perp; dt=dt0 + Day(1), fill_price=order_perp.price, bid=order_perp.price, ask=order_perp.price, last=order_perp.price)
    @test trade_perp isa Trade
    @test Fastback.check_invariants(acc)

    update_marks!(acc, inst_perp, dt0 + Day(2), 55.0, 55.0, 55.0)
    @test Fastback.check_invariants(acc)

    accrue_interest!(acc, dt0 + Day(3))
    @test Fastback.check_invariants(acc)
end
