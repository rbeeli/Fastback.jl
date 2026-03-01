using Dates
using TestItemRunner

@testitem "portfolio_weights_collector" begin
    using Test, Fastback, Dates, Tables

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
    )
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000.0)

    inst_a = spot_instrument(:AAA, :AAA, :USD)
    inst_b = spot_instrument(:BBB, :BBB, :USD)
    inst_a = register_instrument!(acc, inst_a)
    inst_b = register_instrument!(acc, inst_b)

    dt_open = DateTime(2020, 1, 1, 9, 0, 0)
    order_a = Order(oid!(acc), inst_a, dt_open, 100.0, 1.0)
    fill_order!(acc, order_a; dt=dt_open, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    order_b = Order(oid!(acc), inst_b, dt_open, 200.0, 1.0)
    fill_order!(acc, order_b; dt=dt_open, fill_price=200.0, bid=200.0, ask=200.0, last=200.0)

    collect_weights, collected = portfolio_weights_collector(acc, [inst_a, inst_b], Day(1); cash=usd)

    dt1 = DateTime(2020, 1, 1, 10, 0, 0)
    dt2 = DateTime(2020, 1, 1, 20, 0, 0)
    dt3 = DateTime(2020, 1, 2, 10, 0, 0)

    update_marks!(acc, inst_a, dt1, 100.0, 100.0, 100.0)
    update_marks!(acc, inst_b, dt1, 200.0, 200.0, 200.0)
    should_collect(collected, dt1) && collect_weights(dt1)

    update_marks!(acc, inst_a, dt2, 110.0, 110.0, 110.0)
    update_marks!(acc, inst_b, dt2, 190.0, 190.0, 190.0)
    should_collect(collected, dt2) && collect_weights(dt2)

    update_marks!(acc, inst_a, dt3, 120.0, 120.0, 120.0)
    update_marks!(acc, inst_b, dt3, 180.0, 180.0, 180.0)
    should_collect(collected, dt3) && collect_weights(dt3)

    @test dates(collected) == [dt1, dt3]
    @test collected.symbols == [:AAA, :BBB]
    @test length(values(collected)) == 2
    @test values(collected)[1] ≈ [0.1, 0.12]
    @test values(collected)[2] ≈ [0.2, 0.18]
    @test collected.last_dt == dt3
    @test Tables.schema(collected).names == (:date, :AAA, :BBB)
    rows = collect(Tables.rows(collected))
    @test rows[1].AAA ≈ 0.1
    @test rows[2].BBB ≈ 0.18
end

@testitem "portfolio_weights_collector zero equity" begin
    using Test, Fastback, Dates

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
    )
    inst = spot_instrument(:AAA, :AAA, :USD)
    inst = register_instrument!(acc, inst)

    collect_weights, collected = portfolio_weights_collector(acc, [inst], Day(1))
    dt = DateTime(2020, 1, 1, 10, 0, 0)
    should_collect(collected, dt) && collect_weights(dt)

    @test dates(collected) == [dt]
    @test collected.symbols == [:AAA]
    @test values(collected)[1] == [0.0]
end

@testitem "portfolio_weights_collector variation margin uses signed notional" begin
    using Test, Fastback, Dates

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
    )
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(acc, future_instrument(
        :FUTUSD,
        :FUT,
        :USD;
        expiry=DateTime(2030, 1, 1),
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        multiplier=2.0,
    ))

    dt_open = DateTime(2020, 1, 1, 9, 0, 0)
    order = Order(oid!(acc), inst, dt_open, 100.0, 1.0)
    fill_order!(acc, order; dt=dt_open, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    dt_mark = DateTime(2020, 1, 1, 10, 0, 0)
    update_marks!(acc, inst, dt_mark, 110.0, 110.0, 110.0)

    collect_weights, collected = portfolio_weights_collector(acc, [inst], Day(1); cash=usd)
    should_collect(collected, dt_mark) && collect_weights(dt_mark)

    pos = get_position(acc, inst)
    expected_weight = pos.quantity * abs(pos.mark_price) * inst.spec.multiplier / equity(acc, usd)
    @test values(collected)[1] ≈ [expected_weight]
    @test values(collected)[1][1] != 0.0
end

@testitem "portfolio_weights_collector short variation margin has negative weight" begin
    using Test, Fastback, Dates

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
    )
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(acc, future_instrument(
        :FUTUSD_SHORT,
        :FUT,
        :USD;
        expiry=DateTime(2030, 1, 1),
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        multiplier=2.0,
    ))

    dt_open = DateTime(2020, 1, 1, 9, 0, 0)
    order = Order(oid!(acc), inst, dt_open, 100.0, -1.0)
    fill_order!(acc, order; dt=dt_open, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    dt_mark = DateTime(2020, 1, 1, 10, 0, 0)
    update_marks!(acc, inst, dt_mark, 100.0, 100.0, 100.0)

    collect_weights, collected = portfolio_weights_collector(acc, [inst], Day(1); cash=usd)
    should_collect(collected, dt_mark) && collect_weights(dt_mark)

    pos = get_position(acc, inst)
    expected_weight = pos.quantity * abs(pos.mark_price) * inst.spec.multiplier / equity(acc, usd)
    @test values(collected)[1] ≈ [expected_weight]
    @test values(collected)[1][1] < 0.0
end

@testitem "portfolio_weights_collector long and short notionals keep opposite signs" begin
    using Test, Fastback, Dates

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
    )
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 10_000.0)

    inst_long = register_instrument!(acc, future_instrument(
        :FUT_LONG,
        :FUTL,
        :USD;
        expiry=DateTime(2030, 1, 1),
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        multiplier=1.0,
    ))
    inst_short = register_instrument!(acc, future_instrument(
        :FUT_SHORT,
        :FUTS,
        :USD;
        expiry=DateTime(2030, 1, 1),
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        multiplier=1.0,
    ))

    dt_open = DateTime(2020, 1, 1, 9, 0, 0)
    order_long = Order(oid!(acc), inst_long, dt_open, 100.0, 1.0)
    fill_order!(acc, order_long; dt=dt_open, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    order_short = Order(oid!(acc), inst_short, dt_open, 100.0, -1.0)
    fill_order!(acc, order_short; dt=dt_open, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    dt_mark = DateTime(2020, 1, 1, 10, 0, 0)
    update_marks!(acc, inst_long, dt_mark, 100.0, 100.0, 100.0)
    update_marks!(acc, inst_short, dt_mark, 100.0, 100.0, 100.0)

    collect_weights, collected = portfolio_weights_collector(acc, [inst_long, inst_short], Day(1); cash=usd)
    should_collect(collected, dt_mark) && collect_weights(dt_mark)

    expected_long = get_position(acc, inst_long).quantity * 100.0 / equity(acc, usd)
    expected_short = get_position(acc, inst_short).quantity * 100.0 / equity(acc, usd)

    @test values(collected)[1] ≈ [expected_long]
    @test values(collected)[2] ≈ [expected_short]
    @test values(collected)[1][1] > 0.0
    @test values(collected)[2][1] < 0.0
    @test values(collected)[1][1] + values(collected)[2][1] ≈ 0.0 atol=1e-12
end

@testitem "portfolio_weights_collector converts quote notionals into target cash" begin
    using Test, Fastback, Dates

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:CHF),
        broker=NoOpBroker(),
    )
    register_cash_asset!(acc, CashSpec(:USD))
    chf = cash_asset(acc, :CHF)
    usd = cash_asset(acc, :USD)
    update_rate!(acc, usd, chf, 0.5)
    deposit!(acc, :CHF, 100.0)
    deposit!(acc, :USD, 100.0)

    inst = register_instrument!(acc, spot_instrument(:AAAUSD, :AAA, :USD))
    dt = DateTime(2020, 1, 1, 10, 0, 0)
    order = Order(oid!(acc), inst, dt, 100.0, 1.0)
    fill_order!(acc, order; dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    update_marks!(acc, inst, dt, 100.0, 100.0, 100.0)

    collect_chf, collected_chf = portfolio_weights_collector(acc, [inst], Day(1))
    should_collect(collected_chf, dt) && collect_chf(dt)

    pos = get_position(acc, inst)
    notional_quote = pos.quantity * abs(pos.mark_price) * inst.spec.multiplier
    expected_chf = (notional_quote * get_rate(acc, usd, chf)) / equity(acc, chf)
    @test values(collected_chf)[1] ≈ [expected_chf]
    @test values(collected_chf)[1][1] ≈ 0.5

    collect_usd, collected_usd = portfolio_weights_collector(acc, [inst], Day(1); cash=usd)
    should_collect(collected_usd, dt) && collect_usd(dt)
    expected_usd = notional_quote / equity(acc, usd)
    @test values(collected_usd)[1] ≈ [expected_usd]
    @test values(collected_usd)[1][1] ≈ 1.0
end
