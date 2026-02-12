using Dates
using TestItemRunner

@testitem "plan_fill mirrors fill_order! (asset-settled open)" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 1_000.0)

    inst = register_instrument!(acc, spot_instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))
    pos = get_position(acc, inst)

    dt = DateTime(2025, 1, 1)
    price = 10.0
    order = Order(oid!(acc), inst, dt, price, 5.0)

    update_marks!(acc, pos, dt, price, price, price)
    cash_before = cash_balance(acc, usd)
    pos_qty_before = pos.quantity

    commission = 0.5
    commission_pct = 0.001
    plan = plan_fill(
        acc,
        pos,
        order,
        dt,
        price,
        price,
        price,
        order.quantity,
        commission,
        commission_pct,
    )

    @test pos.quantity == pos_qty_before
    @test plan.fill_qty == order.quantity
    @test plan.commission == commission + commission_pct * nominal_value(order)
    @test plan.cash_delta == -(order.quantity * price * inst.multiplier + plan.commission)
    @test plan.realized_pnl_entry == 0.0
    @test plan.realized_pnl_settle == 0.0
    @test plan.new_qty == order.quantity
    @test plan.new_avg_entry_price_quote == price
    @test plan.new_value_quote == order.quantity * price * inst.multiplier
    @test plan.new_pnl_quote == 0.0

    trade = fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price, commission=commission, commission_pct=commission_pct)

    @test trade.fill_qty == plan.fill_qty
    @test trade.remaining_qty == plan.remaining_qty
    @test trade.realized_pnl_entry == plan.realized_pnl_entry
    @test trade.realized_pnl_settle == plan.realized_pnl_settle
    @test trade.realized_qty == plan.realized_qty
    @test trade.commission_settle == plan.commission
    @test trade.cash_delta_settle == plan.cash_delta
    @test pos.quantity == plan.new_qty
    @test pos.avg_entry_price == plan.new_avg_entry_price_quote
    @test pos.avg_settle_price == pos.avg_entry_price
    @test pos.value_quote == plan.new_value_quote
    @test pos.pnl_quote == plan.new_pnl_quote
    @test acc.ledger.init_margin_used[inst.margin_cash_index] == plan.new_init_margin_settle
    @test acc.ledger.maint_margin_used[inst.margin_cash_index] == plan.new_maint_margin_settle
    @test cash_balance(acc, usd) ≈ cash_before + plan.cash_delta atol=1e-12
end

@testitem "fills respect mark price when spreaded" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 100.0)

    inst = register_instrument!(acc, spot_instrument(Symbol("SPRD/USD"), :SPRD, :USD))
    pos = get_position(acc, inst)

    dt = DateTime(2025, 3, 1)
    order = Order(oid!(acc), inst, dt, 11.0, 1.0)

    trade = fill_order!(acc, order; dt=dt, fill_price=order.price, bid=9.0, ask=11.0, last=10.0)

    @test trade isa Trade
    @test pos.mark_price == 9.0
    @test pos.value_quote ≈ 9.0 atol=1e-12
    @test cash_balance(acc, usd) ≈ 89.0 atol=1e-12
    @test equity(acc, usd) ≈ 98.0 atol=1e-12
end

@testitem "cash_delta captures asset principal and commission" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 5_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("SPOT/USD"),
            :SPOT,
            :USD;
            settlement=SettlementStyle.Asset,
            contract_kind=ContractKind.Spot,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.5,
            margin_maint_long=0.25,
            margin_init_short=0.5,
            margin_maint_short=0.25,
            multiplier=1.0,
        ),
    )
    pos = get_position(acc, inst)

    dt = DateTime(2025, 2, 1)
    open_price = 20.0
    open_qty = 3.0
    open_order = Order(oid!(acc), inst, dt, open_price, open_qty)
    fill_order!(acc, open_order; dt=dt, fill_price=open_price, bid=open_price, ask=open_price, last=open_price)

    update_marks!(acc, pos, dt, open_price, open_price, open_price)
    cash_before = cash_balance(acc, usd)

    close_price = 25.0
    close_qty = -2.0
    commission = 0.75
    close_order = Order(oid!(acc), inst, dt, close_price, close_qty)
    plan = plan_fill(
        acc,
        pos,
        close_order,
        dt,
        close_price,
        close_price,
        close_price,
        close_order.quantity,
        commission,
        0.0,
    )

    expected_cash_delta = abs(close_qty) * close_price - commission
    @test plan.cash_delta ≈ expected_cash_delta atol=1e-12

    trade = fill_order!(acc, close_order; dt=dt, fill_price=close_price, bid=close_price, ask=close_price, last=close_price, commission=commission)

    @test trade.cash_delta_settle ≈ expected_cash_delta atol=1e-12
    @test cash_balance(acc, usd) ≈ cash_before + expected_cash_delta atol=1e-12
end

@testitem "plan_fill mirrors fill_order! (variation margin reduce)" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 10_000.0)

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
    fill_order!(acc, order_open; dt=dt_open, fill_price=price_open, bid=price_open, ask=price_open, last=price_open)

    dt_mark = DateTime(2025, 1, 2)
    price_mark = 110.0
    update_marks!(acc, pos, dt_mark, price_mark, price_mark, price_mark)

    cash_before = cash_balance(acc, usd)
    init_before = acc.ledger.init_margin_used[inst.margin_cash_index]
    maint_before = acc.ledger.maint_margin_used[inst.margin_cash_index]
    pos_qty_before = pos.quantity

    order_close = Order(oid!(acc), inst, dt_mark, price_mark, -1.0)
    commission = 0.25
    plan = plan_fill(
        acc,
        pos,
        order_close,
        dt_mark,
        price_mark,
        price_mark,
        price_mark,
        order_close.quantity,
        commission,
        0.0,
    )

    @test pos.quantity == pos_qty_before
    @test plan.fill_qty == -1.0
    @test plan.realized_pnl_entry == 10.0
    @test plan.realized_pnl_settle == 0.0
    @test plan.cash_delta == -commission
    @test plan.new_qty == 1.0
    @test plan.new_avg_entry_price_quote == price_open
    @test plan.new_value_quote == 0.0
    @test plan.new_pnl_quote == 0.0
    @test plan.new_init_margin_settle == abs(plan.new_qty) * price_mark * inst.multiplier * 0.1
    @test plan.new_maint_margin_settle == abs(plan.new_qty) * price_mark * inst.multiplier * 0.05

    trade_close = fill_order!(acc, order_close; dt=dt_mark, fill_price=price_mark, bid=price_mark, ask=price_mark, last=price_mark, commission=commission)

    @test trade_close.realized_pnl_entry == plan.realized_pnl_entry
    @test trade_close.realized_pnl_settle == plan.realized_pnl_settle
    @test trade_close.commission_settle == plan.commission
    @test trade_close.cash_delta_settle == plan.cash_delta
    @test pos.quantity == plan.new_qty
    @test pos.avg_entry_price == plan.new_avg_entry_price_quote
    @test pos.avg_settle_price == price_mark
    @test pos.value_quote == plan.new_value_quote
    @test pos.pnl_quote == plan.new_pnl_quote
    @test acc.ledger.init_margin_used[inst.margin_cash_index] == plan.new_init_margin_settle
    @test acc.ledger.maint_margin_used[inst.margin_cash_index] == plan.new_maint_margin_settle
    @test cash_balance(acc, usd) ≈ cash_before + plan.cash_delta atol=1e-12
    @test acc.ledger.init_margin_used[inst.margin_cash_index] < init_before
    @test acc.ledger.maint_margin_used[inst.margin_cash_index] < maint_before
end

@testitem "variation margin entry spread settles immediately" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("VADD/USD"),
            :VADD,
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

    dt = DateTime(2026, 1, 1)
    mark_price = 100.0
    bid = 99.0
    ask = 101.0

    order = Order(oid!(acc), inst, dt, ask, 1.0)
    plan = plan_fill(
        acc,
        pos,
        order,
        dt,
        order.price,
        mark_price,
        mark_price,
        order.quantity,
        0.0,
        0.0,
    )

    cash_before_fill = cash_balance(acc, usd)
    trade = fill_order!(acc, order; dt=dt, fill_price=order.price, bid=bid, ask=ask, last=mark_price)

    expected_settle = (mark_price - ask) * inst.multiplier

    @test plan.new_qty == 1.0
    @test trade isa Trade
    @test trade.cash_delta_settle ≈ expected_settle atol=1e-12
    @test plan.cash_delta ≈ expected_settle atol=1e-12
    @test cash_balance(acc, usd) ≈ cash_before_fill + expected_settle atol=1e-12
    @test equity(acc, usd) ≈ cash_balance(acc, usd) atol=1e-12
    @test pos.quantity == 1.0
    @test pos.avg_settle_price == mark_price
    @test pos.mark_price == mark_price
    @test pos.value_quote == 0.0
    @test pos.pnl_quote == 0.0
    @test Fastback.check_invariants(acc)
end

@testitem "variation margin entry spread counted in init margin check" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 10.5)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("VMRISK/USD"),
            :VMRISK,
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

    dt = DateTime(2026, 1, 1)
    mark_price = 100.0
    fill_price = 101.0
    qty = 1.0
    order = Order(oid!(acc), inst, dt, fill_price, qty)

    plan = plan_fill(
        acc,
        pos,
        order,
        dt,
        fill_price,
        mark_price,
        mark_price,
        qty,
        0.0,
        0.0,
    )
    err = try
        fill_order!(acc, order; dt=dt, fill_price=fill_price, bid=mark_price, ask=mark_price, last=mark_price)
        nothing
    catch e
        e
    end

    @test plan.cash_delta < 0
    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin
    @test pos.quantity == 0.0
end

@testitem "variation margin partial close realizes cash on settle basis" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("VPART/USD"),
            :VPART,
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

    dt_open = DateTime(2026, 1, 1)
    open_order = Order(oid!(acc), inst, dt_open, 100.0, 10.0)
    fill_order!(acc, open_order; dt=dt_open, fill_price=open_order.price, bid=100.0, ask=100.0, last=100.0)

    dt_reduce = dt_open + Day(1)
    reduce_order = Order(oid!(acc), inst, dt_reduce, 99.0, -4.0)
    commission = 0.5

    plan = plan_fill(
        acc,
        pos,
        reduce_order,
        dt_reduce,
        reduce_order.price,
        100.0,
        100.0,
        reduce_order.quantity,
        commission,
        0.0,
    )

    cash_before = cash_balance(acc, usd)
    trade = fill_order!(acc, reduce_order; dt=dt_reduce, fill_price=reduce_order.price, bid=100.0, ask=100.0, last=100.0, commission=commission)

    @test trade isa Trade
    @test plan.realized_pnl_settle_quote ≈ -4.0 atol=1e-12
    @test plan.realized_pnl_settle ≈ -4.0 atol=1e-12
    @test plan.cash_delta ≈ -4.0 - commission atol=1e-12
    @test trade.cash_delta_settle ≈ plan.cash_delta atol=1e-12
    @test trade.realized_pnl_settle ≈ plan.realized_pnl_settle atol=1e-12
    @test trade.realized_pnl_entry ≈ plan.realized_pnl_entry atol=1e-12
    @test pos.quantity == 6.0
    @test pos.avg_settle_price == 100.0
    @test pos.avg_entry_price == 100.0
    @test pos.pnl_quote == 0.0
    @test cash_balance(acc, usd) ≈ cash_before + plan.cash_delta atol=1e-12
end

@testitem "commission_pct uses absolute notional for negative prices" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 1_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("NEGVM/USD"),
            :NEGVM,
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

    dt = DateTime(2026, 1, 1)
    fill_price = -10.0
    fill_qty = 1.0
    commission_pct = 0.01
    order = Order(oid!(acc), inst, dt, fill_price, fill_qty)

    plan = plan_fill(
        acc,
        pos,
        order,
        dt,
        fill_price,
        fill_price,
        fill_price,
        fill_qty,
        0.0,
        commission_pct,
    )

    @test nominal_value(order) ≈ 10.0 atol=1e-12
    @test plan.commission ≈ 0.1 atol=1e-12
    @test plan.cash_delta ≈ -0.1 atol=1e-12

    cash_before = cash_balance(acc, usd)
    trade = fill_order!(acc, order; dt=dt, fill_price=fill_price, bid=fill_price, ask=fill_price, last=fill_price, commission_pct=commission_pct)

    @test nominal_value(trade) ≈ 10.0 atol=1e-12
    @test trade.commission_settle ≈ 0.1 atol=1e-12
    @test trade.cash_delta_settle ≈ -0.1 atol=1e-12
    @test cash_balance(acc, usd) ≈ cash_before - 0.1 atol=1e-12
end

@testitem "fill_order! rejects non-finite price inputs" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 1_000.0)

    inst = register_instrument!(acc, spot_instrument(Symbol("BADPX/USD"), :BADPX, :USD))
    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 100.0, 1.0)

    bad_inputs = (
        (NaN, 100.0, 100.0, 100.0),
        (100.0, NaN, 100.0, 100.0),
        (100.0, 100.0, NaN, 100.0),
        (100.0, 100.0, 100.0, NaN),
    )

    for (fill_px, bid, ask, last) in bad_inputs
        err = try
            fill_order!(acc, order; dt=dt, fill_price=fill_px, bid=bid, ask=ask, last=last)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
    end

    pos = get_position(acc, inst)
    @test isempty(acc.trades)
    @test pos.quantity == 0.0
    @test cash_balance(acc, usd) == 1_000.0
    @test equity(acc, usd) == 1_000.0
end

@testitem "update_marks! rejects non-finite price inputs" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    usd = cash_asset(acc.ledger, :USD)
    deposit!(acc, :USD, 5_000.0)

    inst = register_instrument!(acc, spot_instrument(Symbol("MARKBAD/USD"), :MARKBAD, :USD))
    dt0 = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    pos = get_position(acc, inst)
    bal_before = cash_balance(acc, usd)
    eq_before = equity(acc, usd)
    mark_before = pos.mark_price
    last_before = pos.last_price
    time_before = pos.mark_time

    bad_marks = (
        (NaN, 100.0, 100.0),
        (100.0, NaN, 100.0),
        (100.0, 100.0, NaN),
    )

    for (bid, ask, last) in bad_marks
        err = try
            update_marks!(acc, inst, dt0 + Hour(1), bid, ask, last)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
    end

    @test cash_balance(acc, usd) == bal_before
    @test equity(acc, usd) == eq_before
    @test pos.mark_price == mark_before
    @test pos.last_price == last_before
    @test pos.mark_time == time_before
end
