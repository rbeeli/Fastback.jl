using Dates
using TestItemRunner

@testitem "Variation margin keeps entry vs settlement basis" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 1_000.0)

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
    fill_order!(acc, open_order, dt_open, open_price)

    @test pos.avg_entry_price ≈ open_price
    @test pos.avg_settle_price ≈ open_price
    @test cash_balance(acc, usd) ≈ 1_000.0

    mark_one = 110.0
    update_pnl!(acc, pos, mark_one)
    @test cash_balance(acc, usd) ≈ 1_000.0 + qty * (mark_one - open_price)
    @test pos.avg_entry_price ≈ open_price
    @test pos.avg_settle_price ≈ mark_one

    mark_two = 105.0
    update_pnl!(acc, pos, mark_two)
    @test cash_balance(acc, usd) ≈ 1_000.0 + qty * (mark_two - open_price)
    @test pos.avg_entry_price ≈ open_price
    @test pos.avg_settle_price ≈ mark_two

    dt_add = dt_open + Day(1)
    add_price = 120.0
    add_qty = 1.0
    cash_before_add = cash_balance(acc, usd)
    add_order = Order(oid!(acc), inst, dt_add, add_price, add_qty)
    fill_order!(acc, add_order, dt_add, add_price)

    expected_entry = (open_price * qty + add_price * add_qty) / (qty + add_qty)
    @test pos.quantity ≈ qty + add_qty
    @test pos.avg_entry_price ≈ expected_entry
    @test pos.avg_settle_price ≈ add_price
    @test cash_balance(acc, usd) ≈ cash_before_add + qty * (add_price - mark_two)
end

@testitem "Variation margin marks should not pay the spread" begin
    using Test, Fastback, Dates

    # Long: bid/ask mark should not settle a spread loss
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)
    deposit!(acc, usd, 1_000.0)

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
    fill_order!(acc, open_order, dt, open_price)

    cash_before = cash_balance(acc, usd)
    bid = 99.0
    ask = 101.0
    update_pnl!(acc, inst, bid, ask)

    @test cash_balance(acc, usd) ≈ cash_before
    @test pos.avg_settle_price ≈ open_price
    @test pos.mark_price ≈ open_price

    # Short: same neutrality should hold
    acc2 = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd2 = Cash(:USD)
    deposit!(acc2, usd2, 1_000.0)

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
    fill_order!(acc2, short_order, dt, open_price)

    cash_before_short = cash_balance(acc2, usd2)
    update_pnl!(acc2, inst2, bid, ask)

    @test cash_balance(acc2, usd2) ≈ cash_before_short
    @test pos2.avg_settle_price ≈ open_price
    @test pos2.mark_price ≈ open_price
end
