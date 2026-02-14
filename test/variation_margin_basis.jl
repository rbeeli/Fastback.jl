using Dates
using TestItemRunner

@testitem "Variation margin keeps entry vs settlement basis" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoBrokerProfile(), mode=AccountMode.Margin, base_currency=base_currency)
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("VM/BASIS"),
            :VM,
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
    qty = 1.0
    open_price = 100.0
    open_order = Order(oid!(acc), inst, dt_open, open_price, qty)
    fill_order!(acc, open_order; dt=dt_open, fill_price=open_price, bid=open_price, ask=open_price, last=open_price)

    @test pos.avg_entry_price ≈ open_price
    @test pos.avg_settle_price ≈ open_price
    @test cash_balance(acc, usd) ≈ 1_000.0

    mark_one = 110.0
    update_marks!(acc, pos, dt_open, mark_one, mark_one, mark_one)
    @test cash_balance(acc, usd) ≈ 1_000.0 + qty * (mark_one - open_price)
    @test pos.avg_entry_price ≈ open_price
    @test pos.avg_settle_price ≈ mark_one

    mark_two = 105.0
    update_marks!(acc, pos, dt_open + Hour(1), mark_two, mark_two, mark_two)
    @test cash_balance(acc, usd) ≈ 1_000.0 + qty * (mark_two - open_price)
    @test pos.avg_entry_price ≈ open_price
    @test pos.avg_settle_price ≈ mark_two

    dt_add = dt_open + Day(1)
    add_price = 120.0
    add_qty = 1.0
    cash_before_add = cash_balance(acc, usd)
    add_order = Order(oid!(acc), inst, dt_add, add_price, add_qty)
    fill_order!(acc, add_order; dt=dt_add, fill_price=add_price, bid=add_price, ask=add_price, last=add_price)

    expected_entry = (open_price * qty + add_price * add_qty) / (qty + add_qty)
    @test pos.quantity ≈ qty + add_qty
    @test pos.avg_entry_price ≈ expected_entry
    @test pos.avg_settle_price ≈ add_price
    @test cash_balance(acc, usd) ≈ cash_before_add + qty * (add_price - mark_two)
end

@testitem "Variation margin marks should not pay the spread" begin
    using Test, Fastback, Dates

    # Long: bid/ask mark should not settle a spread loss
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoBrokerProfile(), mode=AccountMode.Margin, base_currency=base_currency)
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("VM/SPREAD"),
            :VM,
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
    open_price = 100.0
    open_order = Order(oid!(acc), inst, dt, open_price, 1.0)
    fill_order!(acc, open_order; dt=dt, fill_price=open_price, bid=open_price, ask=open_price, last=open_price)

    cash_before = cash_balance(acc, usd)
    bid = 99.0
    ask = 101.0
    update_marks!(acc, inst, dt, bid, ask, (bid + ask) / 2)

    @test cash_balance(acc, usd) ≈ cash_before
    @test pos.avg_settle_price ≈ open_price
    @test pos.mark_price ≈ open_price

    # Short: same neutrality should hold
    base_currency=CashSpec(:USD)
    acc2 = Account(; broker=NoBrokerProfile(), mode=AccountMode.Margin, base_currency=base_currency)
    usd2 = cash_asset(acc2.ledger, :USD)
    deposit!(acc2, :USD, 1_000.0)

    inst2 = register_instrument!(
        acc2,
        Instrument(
            Symbol("VM/SPREAD/S"),
            :VM,
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
    pos2 = get_position(acc2, inst2)

    short_order = Order(oid!(acc2), inst2, dt, open_price, -1.0)
    fill_order!(acc2, short_order; dt=dt, fill_price=open_price, bid=open_price, ask=open_price, last=open_price)

    cash_before_short = cash_balance(acc2, usd2)
    update_marks!(acc2, inst2, dt, bid, ask, (bid + ask) / 2)

    @test cash_balance(acc2, usd2) ≈ cash_before_short
    @test pos2.avg_settle_price ≈ open_price
    @test pos2.mark_price ≈ open_price
end
