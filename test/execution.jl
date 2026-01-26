using Dates
using TestItemRunner

@testitem "plan_fill mirrors fill_order! (cash-settled open)" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 1_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD; margin_mode=MarginMode.PercentNotional))
    pos = get_position(acc, inst)

    dt = DateTime(2025, 1, 1)
    price = 10.0
    order = Order(oid!(acc), inst, dt, price, 5.0)

    update_marks!(acc, pos; dt=dt, close_price=price)
    cash_before = cash_balance(acc, usd)
    pos_qty_before = pos.quantity

    commission = 0.5
    commission_pct = 0.001
    plan = plan_fill(acc, pos, order, dt, price; commission=commission, commission_pct=commission_pct)

    @test pos.quantity == pos_qty_before
    @test plan.fill_qty == order.quantity
    @test plan.commission == commission + commission_pct * nominal_value(order)
    @test plan.cash_delta == -(plan.commission)
    @test plan.realized_pnl_gross == 0.0
    @test plan.realized_pnl_net == -plan.commission
    @test plan.new_qty == order.quantity
    @test plan.new_avg_entry_price == price
    @test plan.new_value_quote == 0.0
    @test plan.new_pnl_quote == 0.0

    trade = fill_order!(acc, order, dt, price; commission=commission, commission_pct=commission_pct)

    @test trade.fill_qty == plan.fill_qty
    @test trade.remaining_qty == plan.remaining_qty
    @test trade.realized_pnl == plan.realized_pnl_net
    @test trade.realized_qty == plan.realized_qty
    @test trade.commission == plan.commission
    @test trade.cash_delta == plan.cash_delta
    @test pos.quantity == plan.new_qty
    @test pos.avg_entry_price == plan.new_avg_entry_price
    @test pos.avg_settle_price == pos.avg_entry_price
    @test pos.value_quote == plan.new_value_quote
    @test pos.pnl_quote == plan.new_pnl_quote
    @test acc.init_margin_used[inst.quote_cash_index] == plan.new_init_margin_settle
    @test acc.maint_margin_used[inst.quote_cash_index] == plan.new_maint_margin_settle
    @test cash_balance(acc, usd) ≈ cash_before + plan.cash_delta atol=1e-12
end

@testitem "cash_delta captures asset-settled outlay" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 5_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("SPOT/USD"),
            :SPOT,
            :USD;
            settlement=SettlementStyle.Asset,
            contract_kind=ContractKind.Spot,
            delivery_style=DeliveryStyle.PhysicalDeliver,
            multiplier=1.0,
        ),
    )
    pos = get_position(acc, inst)

    dt = DateTime(2025, 2, 1)
    price = 20.0
    qty = 3.0
    commission = 0.75

    update_marks!(acc, pos; dt=dt, close_price=price)
    cash_before = cash_balance(acc, usd)

    order = Order(oid!(acc), inst, dt, price, qty)
    plan = plan_fill(acc, pos, order, dt, price; commission=commission)

    expected_cash_delta = -(price * qty * inst.multiplier) - commission
    @test plan.cash_delta ≈ expected_cash_delta atol=1e-12

    trade = fill_order!(acc, order, dt, price; commission=commission)

    @test trade.cash_delta ≈ expected_cash_delta atol=1e-12
    @test cash_balance(acc, usd) ≈ cash_before + expected_cash_delta atol=1e-12
end

@testitem "plan_fill mirrors fill_order! (variation margin reduce)" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
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
    update_marks!(acc, pos; dt=dt_mark, close_price=price_mark)

    cash_before = cash_balance(acc, usd)
    init_before = acc.init_margin_used[inst.quote_cash_index]
    maint_before = acc.maint_margin_used[inst.quote_cash_index]
    pos_qty_before = pos.quantity

    order_close = Order(oid!(acc), inst, dt_mark, price_mark, -1.0)
    commission = 0.25
    plan = plan_fill(acc, pos, order_close, dt_mark, price_mark; commission=commission)

    @test pos.quantity == pos_qty_before
    @test plan.fill_qty == -1.0
    @test plan.realized_pnl_gross == 10.0
    @test plan.cash_delta == -commission
    @test plan.new_qty == 1.0
    @test plan.new_avg_entry_price == price_open
    @test plan.new_value_quote == 0.0
    @test plan.new_pnl_quote == 0.0
    @test plan.realized_pnl_net == plan.realized_pnl_gross - commission
    @test plan.new_init_margin_settle == abs(plan.new_qty) * price_mark * inst.multiplier * 0.1
    @test plan.new_maint_margin_settle == abs(plan.new_qty) * price_mark * inst.multiplier * 0.05

    trade_close = fill_order!(acc, order_close, dt_mark, price_mark; commission=commission)

    @test trade_close.realized_pnl == plan.realized_pnl_net
    @test trade_close.commission == plan.commission
    @test trade_close.cash_delta == plan.cash_delta
    @test pos.quantity == plan.new_qty
    @test pos.avg_entry_price == plan.new_avg_entry_price
    @test pos.avg_settle_price == price_mark
    @test pos.value_quote == plan.new_value_quote
    @test pos.pnl_quote == plan.new_pnl_quote
    @test acc.init_margin_used[inst.quote_cash_index] == plan.new_init_margin_settle
    @test acc.maint_margin_used[inst.quote_cash_index] == plan.new_maint_margin_settle
    @test cash_balance(acc, usd) ≈ cash_before + plan.cash_delta atol=1e-12
    @test acc.init_margin_used[inst.quote_cash_index] < init_before
    @test acc.maint_margin_used[inst.quote_cash_index] < maint_before
end
