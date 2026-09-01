using TestItemRunner

@testitem "notional sizing is tick-safe and clamps to inward bounds" begin
    using Test, Fastback

    decimal = Instrument(
        1,
        1,
        1,
        1,
        InstrumentSpec(
            Symbol("DECIMAL/USD"),
            :DECIMAL,
            :USD;
            base_tick=0.1,
            margin_init_long=1.0,
            margin_init_short=1.0,
            margin_maint_long=1.0,
            margin_maint_short=1.0,
        ),
    )
    @test calc_base_qty_for_notional(decimal, 1.0, 0.3) ≈ 0.3 atol=1e-15
    @test calc_base_qty_for_notional(decimal, 1.0, -0.3) ≈ -0.3 atol=1e-15

    bounded = Instrument(
        2,
        1,
        1,
        1,
        InstrumentSpec(
            Symbol("BOUNDED/USD"),
            :BOUNDED,
            :USD;
            base_tick=0.1,
            base_min=0.15,
            base_max=0.36,
            margin_init_long=1.0,
            margin_init_short=1.0,
            margin_maint_long=1.0,
            margin_maint_short=1.0,
        ),
    )
    @test calc_base_qty_for_notional(bounded, 1.0, 1_000.0) ≈ 0.3 atol=1e-15
    @test calc_base_qty_for_notional(bounded, 1.0, 0.0) ≈ 0.2 atol=1e-15
    @test_throws ArgumentError calc_base_qty_for_notional(decimal, 0.0, 1.0)
    @test_throws ArgumentError calc_base_qty_for_notional(decimal, Inf, 1.0)
    @test_throws ArgumentError calc_base_qty_for_notional(decimal, 1.0, NaN)
end

@testitem "instrument, cash, and ledger inputs reject invalid numerics" begin
    using Test, Fastback, Dates

    @test_throws ArgumentError CashSpec(Symbol(""))
    @test_throws ArgumentError CashSpec(Symbol("   "))

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 100.0)
    balance_before = cash_balance(acc, cash_asset(acc, :USD))
    @test_throws ArgumentError deposit!(acc, :USD, NaN)
    @test_throws ArgumentError deposit!(acc, :USD, Inf)
    @test_throws ArgumentError withdraw!(acc, :USD, NaN)
    @test cash_balance(acc, cash_asset(acc, :USD)) == balance_before

    other = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    foreign_cash = cash_asset(other, :USD)
    @test_throws ArgumentError deposit!(acc, foreign_cash, 1.0)
    @test_throws ArgumentError cash_balance(acc, foreign_cash)
    @test cash_balance(acc, cash_asset(acc, :USD)) == balance_before

    function candidate(symbol; kwargs...)
        InstrumentSpec(
            symbol,
            :BAD,
            :USD;
            margin_init_long=1.0,
            margin_init_short=1.0,
            margin_maint_long=1.0,
            margin_maint_short=1.0,
            kwargs...,
        )
    end
    @test_throws ArgumentError register_instrument!(acc, candidate(Symbol(" ")))
    @test_throws ArgumentError register_instrument!(acc, candidate(:BAD_TICK; base_tick=0.0))
    @test_throws ArgumentError register_instrument!(acc, candidate(:BAD_QUOTE; quote_tick=Inf))
    @test_throws ArgumentError register_instrument!(acc, candidate(:BAD_BOUNDS; base_min=0.01, base_max=0.09, base_tick=0.1))
    @test_throws ArgumentError register_instrument!(acc, candidate(:BAD_DIGITS; base_digits=-1))
    @test_throws ArgumentError register_instrument!(acc, candidate(:BAD_BORROW; short_borrow_rate=-0.1))
    @test_throws ArgumentError register_instrument!(acc, candidate(
        :BAD_EXPIRY;
        expiry=DateTime(2028, 1, 2),
    ))
end

@testitem "fills validate quantities, ownership, quotes, and account time before mutation" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 1_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("SAFE/USD"), :SAFE, :USD))
    dt = DateTime(2028, 1, 2)

    function try_fill(order; fill_qty=0.0, bid=100.0, ask=100.0, underlying_price=NaN, fill_dt=dt)
        fill_order!(
            acc,
            order;
            dt=fill_dt,
            fill_price=100.0,
            fill_qty=fill_qty,
            bid=bid,
            ask=ask,
            last=100.0,
            underlying_price=underlying_price,
        )
    end

    @test_throws ArgumentError try_fill(Order(oid!(acc), inst, dt, 100.0, 1.0); fill_qty=2.0)
    @test_throws ArgumentError try_fill(Order(oid!(acc), inst, dt, 100.0, 1.0); fill_qty=-0.5)
    @test_throws ArgumentError try_fill(Order(oid!(acc), inst, dt, 100.0, 0.0))
    @test_throws ArgumentError try_fill(Order(oid!(acc), inst, dt, NaN, 1.0))
    @test_throws ArgumentError try_fill(Order(oid!(acc), inst, dt, 100.0, 1.0); bid=101.0, ask=100.0)
    @test_throws ArgumentError try_fill(Order(oid!(acc), inst, dt, 100.0, 1.0); underlying_price=100.0)
    @test_throws ArgumentError try_fill(
        Order(oid!(acc), inst, dt, 100.0, 1.0);
        fill_dt=dt - Day(1),
    )

    other = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    foreign = register_instrument!(other, spot_instrument(Symbol("FOREIGN/USD"), :FOREIGN, :USD))
    @test_throws ArgumentError get_position(acc, foreign)
    @test_throws ArgumentError try_fill(Order(oid!(other), foreign, dt, 100.0, 1.0))

    @test isempty(acc.trades)
    @test get_position(acc, inst).quantity == 0.0
    @test isnan(get_position(acc, inst).mark_price)
    @test acc.last_event_dt == DateTime(0)

    partial = try_fill(Order(oid!(acc), inst, dt, 100.0, 1.0); fill_qty=0.5)
    @test partial.fill_qty == 0.5
    @test partial.remaining_qty == 0.5
    @test acc.last_event_dt == dt
    @test_throws ArgumentError update_marks!(acc, inst, dt - Millisecond(1), 100.0, 100.0, 100.0)
    @test acc.last_event_dt == dt
end

@testitem "rejected ordinary fills leave mark, financing, ledger, and history unchanged" begin
    using Test, Fastback, Dates

    function account_state(acc, pos)
        position = (
            pos.avg_entry_price,
            pos.avg_entry_price_settle,
            pos.avg_settle_price,
            pos.quantity,
            pos.entry_commission_quote_carry,
            pos.variation_margin_pnl_settle_carry,
            pos.pending_split_factor,
            pos.pnl_quote,
            pos.pnl_settle,
            pos.value_quote,
            pos.value_settle,
            pos.init_margin_settle,
            pos.maint_margin_settle,
            pos.mark_price,
            pos.last_bid,
            pos.last_ask,
            pos.last_price,
            pos.mark_time,
            pos.borrow_fee_dt,
            pos.last_order,
            pos.last_trade,
        )
        (
            copy(acc.ledger.balances),
            copy(acc.ledger.equities),
            copy(acc.ledger.init_margin_used),
            copy(acc.ledger.maint_margin_used),
            position,
            copy(acc.trades),
            copy(acc.cashflows),
            acc.order_sequence,
            acc.trade_sequence,
            acc.trade_count,
            acc.cashflow_sequence,
            acc.last_event_dt,
            acc.last_interest_dt,
        )
    end

    fully_funded = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.FullyFunded,
        base_currency=CashSpec(:USD),
    )
    deposit!(fully_funded, :USD, 1_000.0)
    spot = register_instrument!(fully_funded, spot_instrument(Symbol("ATOMIC/USD"), :ATOMIC, :USD))
    dt0 = DateTime(2028, 1, 2)
    rejected_short = Order(oid!(fully_funded), spot, dt0, 10.0, -1.0)
    flat = get_position(fully_funded, spot)
    before_short = account_state(fully_funded, flat)

    @test_throws OrderRejectError fill_order!(
        fully_funded,
        rejected_short;
        dt=dt0,
        fill_price=10.0,
        bid=9.0,
        ask=11.0,
        last=10.0,
    )
    @test isequal(account_state(fully_funded, flat), before_short)
    @test Fastback.check_invariants(fully_funded)

    margined = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(margined, :USD, 100.0)
    borrowable = register_instrument!(margined, spot_instrument(
        Symbol("BORROW_ATOMIC/USD"),
        :BORROW_ATOMIC,
        :USD;
        short_borrow_rate=0.365,
        margin_init_long=1.0,
        margin_init_short=1.0,
        margin_maint_long=0.5,
        margin_maint_short=0.5,
    ))
    fill_order!(
        margined,
        Order(oid!(margined), borrowable, dt0, 100.0, -0.5);
        dt=dt0,
        fill_price=100.0,
        bid=100.0,
        ask=100.0,
        last=100.0,
    )
    short_pos = get_position(margined, borrowable)
    rejected_increase = Order(oid!(margined), borrowable, dt0 + Day(1), 110.0, -2.0)
    before_margin = account_state(margined, short_pos)

    @test_throws OrderRejectError fill_order!(
        margined,
        rejected_increase;
        dt=dt0 + Day(1),
        fill_price=110.0,
        bid=110.0,
        ask=110.0,
        last=110.0,
    )
    @test isequal(account_state(margined, short_pos), before_margin)
    @test Fastback.check_invariants(margined)

    cross_currency = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        margin_aggregation=MarginAggregation.PerCurrency,
        base_currency=CashSpec(:USD),
    )
    register_cash_asset!(cross_currency, CashSpec(:EUR))
    deposit!(cross_currency, :EUR, 1_000.0)
    eur_spot = register_instrument!(cross_currency, spot_instrument(
        Symbol("NO_BASE_FX/EUR"),
        :NO_BASE_FX,
        :EUR;
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))
    eur_pos = get_position(cross_currency, eur_spot)
    missing_fx_order = Order(oid!(cross_currency), eur_spot, dt0, 100.0, 1.0)
    before_fx = account_state(cross_currency, eur_pos)

    @test_throws ArgumentError fill_order!(
        cross_currency,
        missing_fx_order;
        dt=dt0,
        fill_price=100.0,
        bid=100.0,
        ask=100.0,
        last=100.0,
    )
    @test isequal(account_state(cross_currency, eur_pos), before_fx)
    @test Fastback.check_invariants(cross_currency)
end

@testitem "market steps coalesce final observations and poison on failure" begin
    using Test, Fastback, Dates

    function setup_account()
        acc = Account(;
            broker=NoOpBroker(),
            funding=AccountFunding.Margined,
            base_currency=CashSpec(:USD),
            exchange_rates=ExchangeRates(),
        )
        usd = cash_asset(acc, :USD)
        eur = register_cash_asset!(acc, CashSpec(:EUR))
        update_rate!(acc, eur, usd, 1.0)
        deposit!(acc, :USD, 10_000.0)
        inst = register_instrument!(acc, spot_instrument(
            Symbol("SNAP/EUR"),
            :SNAP,
            :EUR;
            settle_symbol=:USD,
            margin_symbol=:USD,
            margin_init_long=0.5,
            margin_init_short=0.5,
            margin_maint_long=0.25,
            margin_maint_short=0.25,
        ))
        dt0 = DateTime(2028, 1, 2)
        fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0);
            dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
        acc, usd, eur, inst, dt0
    end

    acc, usd, eur, inst, dt0 = setup_account()
    dt1 = dt0 + Day(1)
    process_step!(
        acc,
        dt1;
        fx_updates=[FXUpdate(eur, usd, floatmax(Float64)), FXUpdate(eur, usd, 2.0)],
        marks=[
            MarkUpdate(inst.index, floatmax(Float64) / 4.0, floatmax(Float64) / 4.0, floatmax(Float64) / 4.0),
            MarkUpdate(inst.index, 109.0, 111.0, 110.0),
        ],
        expiries=false,
        accrue_interest=false,
        accrue_borrow_fees=false,
    )
    pos = get_position(acc, inst)
    @test get_rate(acc, eur, usd) == 2.0
    @test pos.value_settle == 218.0
    @test pos.pnl_settle == 118.0
    @test pos.init_margin_settle == 110.0
    @test acc.last_event_dt == dt1

    @test_throws ArgumentError process_step!(
        acc,
        dt1 + Day(1);
        fx_updates=[FXUpdate(eur, usd, floatmax(Float64))],
        marks=[MarkUpdate(inst.index, 120.0, 120.0, 120.0)],
        expiries=false,
        accrue_interest=false,
        accrue_borrow_fees=false,
    )
    @test acc.poisoned
    @test get_rate(acc, eur, usd) == floatmax(Float64)
    @test_throws AccountPoisonedError process_step!(
        acc,
        dt1 + Day(2);
        expiries=false,
        accrue_interest=false,
        accrue_borrow_fees=false,
    )

    invalid_acc, _, _, invalid_inst, invalid_dt = setup_account()
    @test_throws ArgumentError process_step!(
        invalid_acc,
        invalid_dt + Hour(1);
        marks=[MarkUpdate(invalid_inst.index, 101.0, 100.0, 100.5)],
        expiries=false,
    )
    @test invalid_acc.poisoned
end

@testitem "single-mark numeric overflow poisons process_step!" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 100.0)
    spec = InstrumentSpec(
        Symbol("ATOMIC_MARK/USD"),
        :ATOMIC_MARK,
        :USD;
        margin_init_long=4.0,
        margin_init_short=4.0,
        margin_maint_long=2.0,
        margin_maint_short=2.0,
    )
    inst = @test_logs (:warn, r"PercentNotional") register_instrument!(acc, spec)
    dt0 = DateTime(2028, 1, 2)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 1.0, 1.0);
        dt=dt0, fill_price=1.0, bid=1.0, ask=1.0, last=1.0)
    pos = get_position(acc, inst)
    huge = floatmax(Float64) / 2.0

    @test_throws ArgumentError process_step!(
        acc,
        dt0 + Day(1);
        marks=[MarkUpdate(inst.index, huge, huge, huge)],
        expiries=false,
        accrue_interest=false,
        accrue_borrow_fees=false,
    )
    @test acc.poisoned
    @test_throws AccountPoisonedError process_step!(
        acc,
        dt0 + Day(2);
        expiries=false,
        accrue_interest=false,
        accrue_borrow_fees=false,
    )
end

@testitem "expiry batches keep completed settlements and poison on failure" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 10_000.0)
    dt0 = DateTime(2028, 1, 2)
    expiry = dt0 + Day(5)

    function expiring_future(symbol)
        future_instrument(
            symbol,
            symbol,
            :USD;
            expiry=expiry,
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
        )
    end

    first = register_instrument!(acc, expiring_future(:FIRST_EXPIRY))
    second = register_instrument!(acc, expiring_future(:SECOND_EXPIRY))
    for inst in (first, second)
        fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0);
            dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    end

    first_pos = get_position(acc, first)
    second_pos = get_position(acc, second)
    second_pos.mark_price = NaN
    @test_throws ArgumentError process_expiries!(acc, expiry)
    @test first_pos.quantity == 0.0
    @test second_pos.quantity == 1.0
    @test count(t -> t.reason == TradeReason.Expiry, acc.trades) == 1
    @test acc.last_event_dt == expiry
    @test acc.poisoned
    @test isnan(second_pos.mark_price)
    @test_throws AccountPoisonedError process_expiries!(acc, expiry)
end

@testitem "margin invariants are independent of synchronized cache corruption" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(
        Symbol("INVARIANT/USD"),
        :INVARIANT,
        :USD;
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))
    dt = DateTime(2028, 1, 2)
    fill_order!(acc, Order(oid!(acc), inst, dt, 100.0, 2.0);
        dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    @test Fastback.check_invariants(acc)
    @test_throws ArgumentError Fastback.check_invariants(acc; atol=-1.0)
    @test_throws ArgumentError Fastback.check_invariants(acc; rtol=Inf)

    pos = get_position(acc, inst)
    pos.variation_margin_pnl_settle_carry = 1.0
    @test_throws AssertionError Fastback.check_invariants(acc)
    pos.variation_margin_pnl_settle_carry = 0.0
    margin_index = inst.margin_cash_index
    pos.init_margin_settle += 7.0
    acc.ledger.init_margin_used[margin_index] += 7.0
    @test_throws AssertionError Fastback.check_invariants(acc)
end
