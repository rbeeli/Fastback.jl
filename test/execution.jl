using Dates
using TestItemRunner

@testitem "compute_fill_impact mirrors fill_order! (cash-settled open)" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin)
    usd = Cash(:USD)
    deposit!(acc, usd, 1_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))
    pos = get_position(acc, inst)

    dt = DateTime(2025, 1, 1)
    price = 10.0
    order = Order(oid!(acc), inst, dt, price, 5.0)

    update_marks!(acc, pos, price)
    cash_before = cash_balance(acc, usd)
    pos_qty_before = pos.quantity

    commission = 0.5
    commission_pct = 0.001
    impact = compute_fill_impact(acc, pos, order, dt, price; commission=commission, commission_pct=commission_pct)

    @test pos.quantity == pos_qty_before
    @test impact.fill_qty == order.quantity
    @test impact.commission == commission + commission_pct * nominal_value(order)
    @test impact.cash_delta == -(impact.commission)
    @test impact.realized_pnl_gross == 0.0
    @test impact.realized_pnl_net == -impact.commission
    @test impact.new_qty == order.quantity
    @test impact.new_avg_entry_price == price
    @test impact.new_value_local == 0.0
    @test impact.new_pnl_local == 0.0

    trade = fill_order!(acc, order, dt, price; commission=commission, commission_pct=commission_pct)

    @test trade.fill_qty == impact.fill_qty
    @test trade.remaining_qty == impact.remaining_qty
    @test trade.realized_pnl == impact.realized_pnl_net
    @test trade.realized_qty == impact.realized_qty
    @test trade.commission == impact.commission
    @test pos.quantity == impact.new_qty
    @test pos.avg_entry_price == impact.new_avg_entry_price
    @test pos.avg_settle_price == pos.avg_entry_price
    @test pos.value_local == impact.new_value_local
    @test pos.pnl_local == impact.new_pnl_local
    @test acc.init_margin_used[inst.quote_cash_index] == impact.new_init_margin
    @test acc.maint_margin_used[inst.quote_cash_index] == impact.new_maint_margin
    @test cash_balance(acc, usd) ≈ cash_before + impact.cash_delta atol=1e-12
end

@testitem "compute_fill_impact mirrors fill_order! (variation margin reduce)" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin)
    usd = Cash(:USD)
    deposit!(acc, usd, 10_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("FUT/USD"),
            :FUT,
            :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
        ),
    )
    pos = get_position(acc, inst)

    dt_open = DateTime(2025, 1, 1)
    price_open = 100.0
    order_open = Order(oid!(acc), inst, dt_open, price_open, 2.0)
    fill_order!(acc, order_open, dt_open, price_open)

    dt_mark = DateTime(2025, 1, 2)
    price_mark = 110.0
    update_marks!(acc, pos, price_mark)

    cash_before = cash_balance(acc, usd)
    init_before = acc.init_margin_used[inst.quote_cash_index]
    maint_before = acc.maint_margin_used[inst.quote_cash_index]
    pos_qty_before = pos.quantity

    order_close = Order(oid!(acc), inst, dt_mark, price_mark, -1.0)
    commission = 0.25
    impact = compute_fill_impact(acc, pos, order_close, dt_mark, price_mark; commission=commission)

    @test pos.quantity == pos_qty_before
    @test impact.fill_qty == -1.0
    @test impact.realized_pnl_gross == 10.0
    @test impact.cash_delta == -commission
    @test impact.new_qty == 1.0
    @test impact.new_avg_entry_price == price_open
    @test impact.new_value_local == 0.0
    @test impact.new_pnl_local == 0.0
    @test impact.realized_pnl_net == impact.realized_pnl_gross - commission
    @test impact.new_init_margin == abs(impact.new_qty) * price_mark * inst.multiplier * 0.1
    @test impact.new_maint_margin == abs(impact.new_qty) * price_mark * inst.multiplier * 0.05

    trade_close = fill_order!(acc, order_close, dt_mark, price_mark; commission=commission)

    @test trade_close.realized_pnl == impact.realized_pnl_net
    @test trade_close.commission == impact.commission
    @test pos.quantity == impact.new_qty
    @test pos.avg_entry_price == impact.new_avg_entry_price
    @test pos.avg_settle_price == price_mark
    @test pos.value_local == impact.new_value_local
    @test pos.pnl_local == impact.new_pnl_local
    @test acc.init_margin_used[inst.quote_cash_index] == impact.new_init_margin
    @test acc.maint_margin_used[inst.quote_cash_index] == impact.new_maint_margin
    @test cash_balance(acc, usd) ≈ cash_before + impact.cash_delta atol=1e-12
    @test acc.init_margin_used[inst.quote_cash_index] < init_before
    @test acc.maint_margin_used[inst.quote_cash_index] < maint_before
end
