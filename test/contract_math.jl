using Dates
using TestItemRunner

@testitem "Asset settlement opens: equity hit is commission only" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 1_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("AST/USD"),
            :AST,
            :USD;
            settlement=SettlementStyle.Asset,
            contract_kind=ContractKind.Spot,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_maint_long=0.05,
            multiplier=1.0,
        ),
    )

    dt = DateTime(2026, 1, 1)
    price = 10.0
    qty = 2.0
    commission = 0.25
    equity_before = equity(acc, usd)

    order = Order(oid!(acc), inst, dt, price, qty)
    trade = fill_order!(acc, order; dt=dt, fill_price=price, commission=commission)
    @test trade isa Trade

    equity_after = equity(acc, usd)
    @test equity_after ≈ equity_before - commission atol=1e-12

    pos = get_position(acc, inst)
    @test pos.value_quote ≈ qty * price * inst.multiplier atol=1e-12
    @test pos.pnl_quote ≈ 0.0 atol=1e-12
end

@testitem "Cash-settled equity tracks PnL, not notional" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 1_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("CSH/USD"),
            :CSH,
            :USD;
            settlement=SettlementStyle.Cash,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_maint_long=0.05,
            multiplier=1.0,
        ),
    )
    pos = get_position(acc, inst)

    dt = DateTime(2026, 1, 2)
    price = 50.0
    qty = 4.0
    order = Order(oid!(acc), inst, dt, price, qty)

    equity_before = equity(acc, usd)
    fill_order!(acc, order; dt=dt, fill_price=price)
    @test equity(acc, usd) ≈ equity_before atol=1e-12

    close_price = 55.0
    update_marks!(acc, pos; dt=dt + Hour(1), close_price=close_price)
    expected_pnl = qty * (close_price - price) * inst.multiplier
    @test equity(acc, usd) ≈ equity_before + expected_pnl atol=1e-12

    # move back below entry to confirm symmetry
    close_price2 = 48.0
    update_marks!(acc, pos; dt=dt + Hour(2), close_price=close_price2)
    expected_pnl2 = qty * (close_price2 - price) * inst.multiplier
    @test equity(acc, usd) ≈ equity_before + expected_pnl2 atol=1e-12
end

@testitem "Variation margin settles PnL to cash and rolls basis" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 5_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("PERP/USD"),
            :PERP,
            :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_maint_long=0.05,
            multiplier=1.0,
        ),
    )
    pos = get_position(acc, inst)

    dt = DateTime(2026, 1, 3)
    price = 100.0
    qty = 1.0
    order = Order(oid!(acc), inst, dt, price, qty)
    fill_order!(acc, order; dt=dt, fill_price=price)

    cash_before = cash_balance(acc, usd)
    update_marks!(acc, pos; dt=dt + Hour(1), close_price=110.0)
    @test cash_balance(acc, usd) ≈ cash_before + 10.0 atol=1e-12
    @test last(acc.cashflows).amount ≈ 10.0 atol=1e-12
    @test pos.pnl_quote == 0.0
    @test pos.avg_settle_price ≈ 110.0 atol=1e-12

    cash_mid = cash_balance(acc, usd)
    update_marks!(acc, pos; dt=dt + Hour(2), close_price=105.0)
    @test cash_balance(acc, usd) ≈ cash_mid - 5.0 atol=1e-12
    @test last(acc.cashflows).amount ≈ -5.0 atol=1e-12
    @test pos.pnl_quote == 0.0
    @test pos.avg_settle_price ≈ 105.0 atol=1e-12
end
