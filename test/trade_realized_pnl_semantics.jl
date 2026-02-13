using Dates
using TestItemRunner

@testitem "opens keep realized P&L at zero while commissions hit cash" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 1_000.0)

    inst = register_instrument!(
        acc,
        spot_instrument(
            Symbol("OPN/USD"),
            :OPN,
            :USD,
        ),
    )

    dt = DateTime(2026, 1, 1)
    commission = 2.5
    order = Order(oid!(acc), inst, dt, 50.0, 10.0)
    trade = fill_order!(acc, order; dt=dt, fill_price=order.price, bid=order.price, ask=order.price, last=order.price, commission=commission)

    @test trade.realized_qty == 0.0
    @test trade.realized_pnl_entry == 0.0
    @test trade.realized_pnl_settle == 0.0
    @test trade.commission_settle ≈ commission atol=1e-12
    @test trade.cash_delta_settle ≈ -(order.quantity * order.price) - commission atol=1e-12
    @test cash_balance(acc, usd) ≈ 1_000.0 - order.quantity * order.price - commission atol=1e-12
    @test equity(acc, usd) ≈ cash_balance(acc, usd) + get_position(acc, inst).value_settle atol=1e-12
end

@testitem "closing fill reports gross realized P&L with commission separate" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 5_000.0)

    inst = register_instrument!(
        acc,
        spot_instrument(
            Symbol("CLS/USD"),
            :CLS,
            :USD,
        ),
    )

    dt_open = DateTime(2026, 1, 1)
    qty = 3.0
    price_open = 100.0
    commission_open = 1.0
    open_order = Order(oid!(acc), inst, dt_open, price_open, qty)
    fill_order!(acc, open_order; dt=dt_open, fill_price=price_open, bid=price_open, ask=price_open, last=price_open, commission=commission_open)

    cash_after_open = cash_balance(acc, usd)

    dt_close = dt_open + Day(1)
    price_close = 110.0
    commission_close = 0.75
    close_order = Order(oid!(acc), inst, dt_close, price_close, -qty)
    close_trade = fill_order!(acc, close_order; dt=dt_close, fill_price=price_close, bid=price_close, ask=price_close, last=price_close, commission=commission_close)

    expected_gross = (price_close - price_open) * qty

    @test close_trade.realized_qty == qty
    @test close_trade.realized_pnl_entry ≈ expected_gross atol=1e-12
    @test close_trade.realized_pnl_settle ≈ expected_gross atol=1e-12
    @test close_trade.commission_settle ≈ commission_close atol=1e-12
    @test close_trade.cash_delta_settle ≈ qty * price_close - commission_close atol=1e-12
    @test cash_balance(acc, usd) ≈ cash_after_open + qty * price_close - commission_close atol=1e-12
    @test equity(acc, usd) ≈ cash_balance(acc, usd) atol=1e-12
end

@testitem "realized_return gated by realized quantity" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    deposit!(acc, :USD, 1_000.0)

    inst = register_instrument!(
        acc,
        spot_instrument(
            Symbol("RET/USD"),
            :RET,
            :USD,
        ),
    )

    dt1 = DateTime(2026, 1, 1)
    order1 = Order(oid!(acc), inst, dt1, 10.0, 1.0)
    fill_order!(acc, order1; dt=dt1, fill_price=order1.price, bid=order1.price, ask=order1.price, last=order1.price)

    dt2 = dt1 + Day(1)
    order2 = Order(oid!(acc), inst, dt2, 12.0, 2.0)
    commission = 0.5
    trade2 = fill_order!(acc, order2; dt=dt2, fill_price=order2.price, bid=order2.price, ask=order2.price, last=order2.price, commission=commission)

    @test trade2.realized_qty == 0.0
    @test trade2.realized_pnl_entry == 0.0
    @test trade2.realized_pnl_settle == 0.0
    @test realized_return(trade2) == 0.0
end

@testitem "realized_return remains sign-consistent at negative prices" begin
    using Test, Fastback, Dates

    function setup_acc(sym::Symbol)
        ledger = CashLedger()
        base_currency = register_cash_asset!(ledger, :USD)
        acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
        deposit!(acc, :USD, 1_000.0)
        inst = register_instrument!(
            acc,
            Instrument(
                sym,
                :RETNEG,
                :USD;
                contract_kind=ContractKind.Spot,
                settlement=SettlementStyle.Asset,
                margin_mode=MarginMode.PercentNotional,
                margin_init_long=0.0,
                margin_init_short=0.0,
                margin_maint_long=0.0,
                margin_maint_short=0.0,
            ),
        )
        return acc, inst
    end

    dt = DateTime(2026, 1, 1)

    acc_long, inst_long = setup_acc(Symbol("RETNEG_LONG/USD"))
    fill_order!(acc_long, Order(oid!(acc_long), inst_long, dt, -10.0, 1.0); dt=dt, fill_price=-10.0, bid=-10.0, ask=-10.0, last=-10.0)
    trade_long = fill_order!(acc_long, Order(oid!(acc_long), inst_long, dt + Day(1), -5.0, -1.0); dt=dt + Day(1), fill_price=-5.0, bid=-5.0, ask=-5.0, last=-5.0)
    @test trade_long.realized_pnl_entry > 0.0
    @test realized_return(trade_long) ≈ 0.5 atol=1e-12

    acc_short, inst_short = setup_acc(Symbol("RETNEG_SHRT/USD"))
    fill_order!(acc_short, Order(oid!(acc_short), inst_short, dt, -10.0, -1.0); dt=dt, fill_price=-10.0, bid=-10.0, ask=-10.0, last=-10.0)
    trade_short = fill_order!(acc_short, Order(oid!(acc_short), inst_short, dt + Day(1), -5.0, 1.0); dt=dt + Day(1), fill_price=-5.0, bid=-5.0, ask=-5.0, last=-5.0)
    @test trade_short.realized_pnl_entry < 0.0
    @test realized_return(trade_short) ≈ -0.5 atol=1e-12
end

@testitem "cross-currency asset realized settle P&L captures principal FX translation" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency, exchange_rates=er)
    add_asset!(er, cash_asset(acc.ledger, :USD))
    register_cash_asset!(acc.ledger, :EUR)
    add_asset!(er, cash_asset(acc.ledger, :EUR))
    deposit!(acc, :USD, 0.0)

    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.1)
    inst = register_instrument!(acc, Instrument(
        Symbol("FXREAL/EURUSD"),
        :FXREAL,
        :EUR;
        settle_symbol=:USD,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.0,
        margin_init_short=0.0,
        margin_maint_long=0.0,
        margin_maint_short=0.0,
    ))

    dt0 = DateTime(2026, 1, 1)
    open_order = Order(oid!(acc), inst, dt0, 100.0, 1.0)
    fill_order!(acc, open_order; dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.2)
    dt1 = dt0 + Day(1)
    close_order = Order(oid!(acc), inst, dt1, 100.0, -1.0)
    close_trade = fill_order!(acc, close_order; dt=dt1, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    # Quote P&L is zero, but settlement P&L realizes principal FX move: 100*(1.2-1.1)=10 USD.
    @test close_trade.realized_pnl_entry ≈ 10.0 atol=1e-12
    @test close_trade.realized_pnl_settle ≈ 10.0 atol=1e-12
    @test cash_balance(acc, cash_asset(acc.ledger, :USD)) ≈ 10.0 atol=1e-12
end

@testitem "cross-currency scale-in uses settlement-entry basis for realized P&L" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency, exchange_rates=er)
    add_asset!(er, cash_asset(acc.ledger, :USD))
    register_cash_asset!(acc.ledger, :EUR)
    add_asset!(er, cash_asset(acc.ledger, :EUR))
    deposit!(acc, :USD, 0.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("FXREAL/SCALE"),
        :FXREAL,
        :EUR;
        settle_symbol=:USD,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.0,
        margin_init_short=0.0,
        margin_maint_long=0.0,
        margin_maint_short=0.0,
    ))

    dt0 = DateTime(2026, 1, 1)

    # First entry: 100 EUR @ 1.0 => 100 USD basis.
    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.0)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    # Second entry: 120 EUR @ 2.0 => 240 USD basis, new settle-entry avg = (100+240)/2 = 170.
    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 2.0)
    fill_order!(acc, Order(oid!(acc), inst, dt0 + Hour(1), 120.0, 1.0); dt=dt0 + Hour(1), fill_price=120.0, bid=120.0, ask=120.0, last=120.0)

    # Partial close: 110 EUR @ 1.5 => 165 USD close basis for realized qty 1.
    # Settlement realized should be 165 - 170 = -5 USD, while quote-basis realized is zero.
    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.5)
    close_trade = fill_order!(acc, Order(oid!(acc), inst, dt0 + Day(1), 110.0, -1.0); dt=dt0 + Day(1), fill_price=110.0, bid=110.0, ask=110.0, last=110.0)

    @test close_trade.realized_pnl_entry ≈ -5.0 atol=1e-12
    @test close_trade.realized_pnl_settle ≈ -5.0 atol=1e-12
    @test get_position(acc, inst).avg_entry_price_settle ≈ 170.0 atol=1e-12
end
