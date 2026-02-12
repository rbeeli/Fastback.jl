using Dates
using TestItemRunner

@testitem "Spot asset-settled open/close updates cash and equity" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(acc, spot_instrument(Symbol("SPOT/USD"), :SPOT, :USD))

    dt0 = DateTime(2026, 1, 1)
    open_price = 101.0
    qty = 10.0
    commission_open = 1.0

    order_open = Order(oid!(acc), inst, dt0, open_price, qty)
    fill_order!(acc, order_open; dt=dt0, fill_price=open_price, bid=99.0, ask=101.0, last=100.0, commission=commission_open)

    cash_after_open = cash_balance(acc, usd)
    @test cash_after_open ≈ 8_989.0 atol=1e-12

    pos = get_position(acc, inst)
    expected_pnl = qty * (pos.mark_price - pos.avg_entry_price) * inst.multiplier
    @test expected_pnl ≈ -20.0 atol=1e-12
    @test equity(acc, usd) ≈ cash_after_open + pos.value_settle atol=1e-12

    dt1 = dt0 + Hour(1)
    close_price = 102.0
    commission_close = 0.5
    order_close = Order(oid!(acc), inst, dt1, close_price, -qty)
    fill_order!(acc, order_close; dt=dt1, fill_price=close_price, bid=close_price, ask=close_price, last=close_price, commission=commission_close)

    @test get_position(acc, inst).quantity == 0.0
    expected_cash = 8_989.0 + qty * close_price - commission_close
    @test cash_balance(acc, usd) ≈ expected_cash atol=1e-12
    @test equity(acc, usd) ≈ cash_balance(acc, usd) atol=1e-12
end

@testitem "Variation margin settles P&L and resets basis" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 5_000.0)

    inst = register_instrument!(acc, perpetual_instrument(Symbol("PERP/USD"), :PERP, :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))

    dt0 = DateTime(2026, 1, 2)
    order = Order(oid!(acc), inst, dt0, 100.0, 1.0)
    fill_order!(acc, order; dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    cash_before = cash_balance(acc, usd)
    update_marks!(acc, inst, dt0 + Hour(1), 110.0, 110.0, 110.0)
    @test cash_balance(acc, usd) ≈ cash_before + 10.0 atol=1e-12
    @test get_position(acc, inst).value_quote == 0.0
    @test get_position(acc, inst).avg_settle_price ≈ 110.0 atol=1e-12

    cash_mid = cash_balance(acc, usd)
    update_marks!(acc, inst, dt0 + Hour(2), 105.0, 105.0, 105.0)
    @test cash_balance(acc, usd) ≈ cash_mid - 5.0 atol=1e-12
    @test get_position(acc, inst).value_quote == 0.0
    @test get_position(acc, inst).avg_settle_price ≈ 105.0 atol=1e-12
end

@testitem "Margin sufficiency rejects exposure increases" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    deposit!(acc, :USD, 100.0)

    inst = register_instrument!(acc, Instrument(Symbol("RISK/USD"), :RISK, :USD;
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))

    dt = DateTime(2026, 1, 3)
    order = Order(oid!(acc), inst, dt, 1_000.0, 1.0)
    err = try
        fill_order!(acc, order; dt=dt, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)
        nothing
    catch e
        e
    end
    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin
end

@testitem "check_invariants holds after fills, marks, FX, and accruals" begin
    using Test, Fastback, Dates

    er = SpotExchangeRates()
    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency, margining_style=MarginingStyle.BaseCurrency, exchange_rates=er)

    usd = cash_asset(acc.ledger, :USD)
    add_asset!(er, usd)
    deposit!(acc, :USD, 10_000.0)
    eur = register_cash_asset!(acc.ledger, :EUR)
    add_asset!(er, eur)
    deposit!(acc, :EUR, 0.0)
    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.1)

    set_interest_rates!(acc, :USD; borrow=0.0, lend=0.01)

    spot = register_instrument!(acc, Instrument(Symbol("SPOT/EURUSD"), :SPOT, :EUR;
        settle_symbol=:USD,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))

    perp = register_instrument!(acc, perpetual_instrument(Symbol("PERP/USD"), :PERP, :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))

    dt0 = DateTime(2026, 1, 5)
    fill_order!(acc, Order(oid!(acc), spot, dt0, 100.0, 2.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), perp, dt0, 50.0, 1.0); dt=dt0, fill_price=50.0, bid=50.0, ask=50.0, last=50.0)

    process_step!(acc, dt0) # initialize clocks

    dt1 = dt0 + Day(1)
    fx_updates = [FXUpdate(cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.2)]
    marks = [
        MarkUpdate(spot.index, 110.0, 110.0, 110.0),
        MarkUpdate(perp.index, 60.0, 60.0, 60.0),
    ]
    funding = [FundingUpdate(perp.index, 0.01)]

    process_step!(acc, dt1; fx_updates=fx_updates, marks=marks, funding=funding)

    @test Fastback.check_invariants(acc)
end
