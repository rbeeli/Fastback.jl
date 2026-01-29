using Dates
using TestItemRunner

@testitem "opens keep realized P&L at zero while commissions hit cash" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 1_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("OPN/USD"),
            :OPN,
            :USD;
            settlement=SettlementStyle.Cash,
            margin_mode=MarginMode.PercentNotional,
        ),
    )

    dt = DateTime(2026, 1, 1)
    commission = 2.5
    order = Order(oid!(acc), inst, dt, 50.0, 10.0)
    trade = fill_order!(acc, order; dt=dt, fill_price=order.price, commission=commission)

    @test trade.realized_qty == 0.0
    @test trade.realized_pnl_entry == 0.0
    @test trade.realized_pnl_settle == 0.0
    @test trade.commission_settle ≈ commission atol=1e-12
    @test trade.cash_delta_settle ≈ -commission atol=1e-12
    @test cash_balance(acc, usd) ≈ 1_000.0 - commission atol=1e-12
    @test equity(acc, usd) ≈ cash_balance(acc, usd) + get_position(acc, inst).value_settle atol=1e-12
end

@testitem "closing fill reports gross realized P&L with commission separate" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 5_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("CLS/USD"),
            :CLS,
            :USD;
            settlement=SettlementStyle.Cash,
            margin_mode=MarginMode.PercentNotional,
        ),
    )

    dt_open = DateTime(2026, 1, 1)
    qty = 3.0
    price_open = 100.0
    commission_open = 1.0
    open_order = Order(oid!(acc), inst, dt_open, price_open, qty)
    fill_order!(acc, open_order; dt=dt_open, fill_price=price_open, commission=commission_open)

    cash_after_open = cash_balance(acc, usd)

    dt_close = dt_open + Day(1)
    price_close = 110.0
    commission_close = 0.75
    close_order = Order(oid!(acc), inst, dt_close, price_close, -qty)
    close_trade = fill_order!(acc, close_order; dt=dt_close, fill_price=price_close, commission=commission_close)

    expected_gross = (price_close - price_open) * qty

    @test close_trade.realized_qty == qty
    @test close_trade.realized_pnl_entry ≈ expected_gross atol=1e-12
    @test close_trade.realized_pnl_settle ≈ expected_gross atol=1e-12
    @test close_trade.commission_settle ≈ commission_close atol=1e-12
    @test close_trade.cash_delta_settle ≈ expected_gross - commission_close atol=1e-12
    @test cash_balance(acc, usd) ≈ cash_after_open + expected_gross - commission_close atol=1e-12
    @test equity(acc, usd) ≈ cash_balance(acc, usd) atol=1e-12
end

@testitem "realized_return gated by realized quantity" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 1_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("RET/USD"),
            :RET,
            :USD;
            settlement=SettlementStyle.Cash,
            margin_mode=MarginMode.PercentNotional,
        ),
    )

    dt1 = DateTime(2026, 1, 1)
    order1 = Order(oid!(acc), inst, dt1, 10.0, 1.0)
    fill_order!(acc, order1; dt=dt1, fill_price=order1.price)

    dt2 = dt1 + Day(1)
    order2 = Order(oid!(acc), inst, dt2, 12.0, 2.0)
    commission = 0.5
    trade2 = fill_order!(acc, order2; dt=dt2, fill_price=order2.price, commission=commission)

    @test trade2.realized_qty == 0.0
    @test trade2.realized_pnl_entry == 0.0
    @test trade2.realized_pnl_settle == 0.0
    @test realized_return(trade2) == 0.0
end
