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
