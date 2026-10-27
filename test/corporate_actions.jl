using TestItemRunner

@testitem "spot split and dividend preserve equity and adjust trade analytics" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(
        Symbol("ACTION/USD"),
        :ACTION,
        :USD;
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))

    dt_open = DateTime(2028, 6, 15, 9)
    fill_order!(
        acc,
        Order(oid!(acc), inst, dt_open, 100.0, 10.0);
        dt=dt_open,
        fill_price=100.0,
        bid=99.0,
        ask=101.0,
        last=100.0,
    )
    equity_before = equity(acc, usd)
    cash_before = cash_balance(acc, usd)

    dt_action = dt_open + Day(1)
    apply_spot_corporate_action!(
        acc,
        inst,
        dt_action;
        split_factor=2.0,
        cash_dividend_per_unit=1.0,
    )

    pos = get_position(acc, inst)
    @test pos.quantity == 20.0
    @test pos.avg_entry_price == 50.0
    @test pos.avg_entry_price_settle == 50.0
    @test pos.avg_settle_price == 50.0
    @test pos.pending_split_factor == 2.0
    @test pos.last_bid == 49.0
    @test pos.last_ask == 50.0
    @test pos.last_price == 49.5
    @test cash_balance(acc, usd) == cash_before + 10.0
    @test equity(acc, usd) ≈ equity_before atol=1e-12
    dividend = only(filter(cf -> cf.kind == CashflowKind.CashDividend, acc.cashflows))
    @test dividend.amount == 10.0
    @test dividend.inst_index == inst.index
    @test Fastback.check_invariants(acc)

    dt_close = dt_action + Day(2)
    close_trade = fill_order!(
        acc,
        Order(oid!(acc), inst, dt_close, 49.0, -20.0);
        dt=dt_close,
        fill_price=49.0,
        bid=49.0,
        ask=50.0,
        last=49.5,
    )
    @test close_trade.preceding_split_factor == 2.0
    @test get_position(acc, inst).pending_split_factor == 1.0
    period = only(realized_holding_periods(acc))
    @test period.quantity == 20.0
    @test period.entry_date == dt_open
    @test period.exit_date == dt_close
    @test Fastback.check_invariants(acc)
end

@testitem "cash dividends debit shorts and corporate-action failures poison the account" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(
        Symbol("SHORTACTION/USD"),
        :SHORTACTION,
        :USD;
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))

    dt_open = DateTime(2028, 6, 15, 9)
    fill_order!(
        acc,
        Order(oid!(acc), inst, dt_open, 100.0, -5.0);
        dt=dt_open,
        fill_price=100.0,
        bid=99.0,
        ask=101.0,
        last=100.0,
    )
    cash_before = cash_balance(acc, usd)
    equity_before = equity(acc, usd)
    dt_action = dt_open + Day(1)
    apply_spot_corporate_action!(acc, inst, dt_action; cash_dividend_per_unit=2.0)

    @test cash_balance(acc, usd) == cash_before - 10.0
    @test equity(acc, usd) ≈ equity_before atol=1e-12
    @test only(filter(cf -> cf.kind == CashflowKind.CashDividend, acc.cashflows)).amount == -10.0

    pos = get_position(acc, inst)
    state_before = (
        pos.quantity,
        pos.avg_entry_price,
        pos.last_bid,
        pos.last_ask,
        pos.last_price,
        cash_balance(acc, usd),
        equity(acc, usd),
        length(acc.cashflows),
        acc.last_event_dt,
    )
    @test_throws ArgumentError apply_spot_corporate_action!(
        acc,
        inst,
        dt_action + Day(1);
        cash_dividend_per_unit=100.0,
    )
    @test (
        pos.quantity,
        pos.avg_entry_price,
        pos.last_bid,
        pos.last_ask,
        pos.last_price,
        cash_balance(acc, usd),
        equity(acc, usd),
        length(acc.cashflows),
        acc.last_event_dt,
    ) == state_before
    @test acc.poisoned
    @test_throws AccountPoisonedError process_step!(
        acc,
        dt_action + Day(2);
        expiries=false,
        accrue_interest=false,
        accrue_borrow_fees=false,
    )
    @test Fastback.check_invariants(acc)
end

@testitem "corporate actions reject unsupported and neutral requests" begin
    using Test, Fastback, Dates

    function setup_account()
        acc = Account(;
            broker=NoOpBroker(),
            funding=AccountFunding.Margined,
            base_currency=CashSpec(:USD),
        )
        deposit!(acc, :USD, 1_000.0)
        spot = register_instrument!(acc, spot_instrument(Symbol("FLAT/USD"), :FLAT, :USD))
        perp = register_instrument!(acc, perpetual_instrument(
            Symbol("PERP/USD"),
            :PERP,
            :USD;
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
        ))
        acc, spot, perp
    end
    dt = DateTime(2028, 6, 15)

    for apply_invalid! in (
        (acc, spot, _) -> apply_spot_corporate_action!(acc, spot, dt),
        (acc, spot, _) -> apply_spot_corporate_action!(acc, spot, dt; split_factor=0.0),
        (acc, spot, _) -> apply_spot_corporate_action!(acc, spot, dt; cash_dividend_per_unit=-1.0),
        (acc, _, perp) -> apply_spot_corporate_action!(acc, perp, dt; split_factor=2.0),
    )
        acc, spot, perp = setup_account()
        @test_throws ArgumentError apply_invalid!(acc, spot, perp)
        @test acc.poisoned
    end

    acc, spot, _ = setup_account()
    apply_spot_corporate_action!(acc, spot, dt; split_factor=2.0)
    @test acc.last_event_dt == dt
    @test isempty(acc.cashflows)
end

@testitem "spot position transfers move a position without a fill and remargin it" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 10_000.0)
    old = register_instrument!(acc, spot_instrument(
        Symbol("OLD/USD"),
        :OLD,
        :USD;
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))
    new = register_instrument!(acc, spot_instrument(
        Symbol("NEW/USD"),
        :NEW,
        :USD;
        margin_init_long=0.4,
        margin_init_short=0.4,
        margin_maint_long=0.2,
        margin_maint_short=0.2,
    ))

    dt_open = DateTime(2028, 6, 15, 9)
    fill_order!(
        acc,
        Order(oid!(acc), old, dt_open, 100.0, 10.0);
        dt=dt_open,
        fill_price=100.0,
        bid=99.0,
        ask=101.0,
        last=100.0,
    )
    apply_spot_corporate_action!(acc, old, dt_open + Hour(1); split_factor=2.0)
    equity_before = equity(acc, usd)
    cash_before = cash_balance(acc, usd)
    trades_before = length(acc.trades)
    cashflows_before = length(acc.cashflows)

    dt_change = dt_open + Day(1)
    transfer_spot_positions!(acc, [old => new], dt_change)

    source = get_position(acc, old)
    target = get_position(acc, new)
    @test source.quantity == 0.0
    @test source.value_settle == 0.0
    @test source.init_margin_settle == 0.0
    @test target.quantity == 20.0
    @test target.avg_entry_price == 50.0
    @test target.avg_entry_price_settle == 50.0
    @test target.pending_split_factor == 2.0
    @test (target.last_bid, target.last_ask, target.last_price) == (49.5, 50.5, 50.0)
    @test target.mark_time == dt_open + Hour(1)
    @test target.init_margin_settle ≈ 20.0 * 50.0 * 0.4
    @test target.maint_margin_settle ≈ 20.0 * 50.0 * 0.2
    @test init_margin_used(acc, usd) ≈ target.init_margin_settle
    @test maint_margin_used(acc, usd) ≈ target.maint_margin_settle
    @test equity(acc, usd) == equity_before
    @test cash_balance(acc, usd) == cash_before
    @test length(acc.trades) == trades_before
    @test length(acc.cashflows) == cashflows_before
    @test acc.last_event_dt == dt_change
    @test Fastback.check_invariants(acc)

    dt_close = dt_change + Day(1)
    close_trade = fill_order!(
        acc,
        Order(oid!(acc), new, dt_close, 55.0, -20.0);
        dt=dt_close,
        fill_price=55.0,
        bid=55.0,
        ask=56.0,
        last=55.5,
    )
    @test close_trade.realized_qty == 20.0
    @test close_trade.fill_pnl_settle ≈ 20.0 * (55.0 - 50.0)
    @test equity(acc, usd) ≈ 10_000.0 + 20.0 * 5.0
    @test Fastback.check_invariants(acc)
end

@testitem "spot position transfers swap positions and carry the borrow clock" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 10_000.0)
    instrument(symbol, rate) = register_instrument!(acc, spot_instrument(
        Symbol("$(symbol)/USD"),
        symbol,
        :USD;
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
        short_borrow_rate=rate,
    ))
    a = instrument(:A, 0.1)
    b = instrument(:B, 0.2)

    dt_open = DateTime(2028, 1, 1)
    fill_order!(acc, Order(oid!(acc), a, dt_open, 100.0, -10.0); dt=dt_open, fill_price=100.0, bid=100.0, ask=100.0,
        last=100.0)
    fill_order!(acc, Order(oid!(acc), b, dt_open, 20.0, 5.0); dt=dt_open, fill_price=20.0, bid=20.0, ask=20.0, last=20.0)
    equity_before = equity(acc, usd)

    dt_change = dt_open + Day(73)
    transfer_spot_positions!(acc, [a => b, b => a], dt_change)

    @test get_position(acc, a).quantity == 5.0
    @test get_position(acc, a).borrow_fee_dt == DateTime(0)
    @test get_position(acc, b).quantity == -10.0
    @test get_position(acc, b).borrow_fee_dt == dt_open
    @test equity(acc, usd) == equity_before
    @test Fastback.check_invariants(acc)

    accrue_borrow_fees!(acc, dt_change)
    fee = only(filter(cf -> cf.kind == CashflowKind.BorrowFee, acc.cashflows))
    @test fee.inst_index == b.index
    @test fee.amount ≈ -10.0 * 100.0 * 0.2 * 73 / 365
    @test Fastback.check_invariants(acc)
end

@testitem "spot position transfers start the borrow clock of a newly borrowed short" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 10_000.0)
    free = register_instrument!(acc, spot_instrument(Symbol("FREE/USD"), :FREE, :USD;
        margin_init_short=0.5, margin_maint_short=0.25))
    borrowed = register_instrument!(acc, spot_instrument(Symbol("BORROWED/USD"), :BORROWED, :USD;
        margin_init_short=0.5, margin_maint_short=0.25, short_borrow_rate=0.1))

    dt_open = DateTime(2028, 1, 1)
    fill_order!(acc, Order(oid!(acc), free, dt_open, 100.0, -10.0); dt=dt_open, fill_price=100.0, bid=100.0, ask=100.0,
        last=100.0)
    dt_change = dt_open + Day(10)
    transfer_spot_positions!(acc, [free => borrowed], dt_change)

    @test get_position(acc, borrowed).borrow_fee_dt == dt_change
    @test get_position(acc, free).borrow_fee_dt == DateTime(0)
    accrue_borrow_fees!(acc, dt_change)
    @test isempty(filter(cf -> cf.kind == CashflowKind.BorrowFee, acc.cashflows))
    @test Fastback.check_invariants(acc)
end

@testitem "invalid spot position transfers leave the account unchanged" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    register_cash_asset!(acc, CashSpec(:EUR))
    deposit!(acc, :USD, 10_000.0)
    spot(symbol, quote_symbol=:USD) = register_instrument!(acc, spot_instrument(Symbol("$(symbol)/$(quote_symbol)"), symbol,
        quote_symbol; margin_init_long=0.5, margin_maint_long=0.25))
    a, b, c, eur = spot(:A), spot(:B), spot(:C), spot(:E, :EUR)
    perp = register_instrument!(acc, perpetual_instrument(Symbol("P/USD"), :P, :USD;
        margin_requirement=MarginRequirement.PercentNotional, margin_init_long=0.1, margin_init_short=0.1,
        margin_maint_long=0.05, margin_maint_short=0.05))

    dt_open = DateTime(2028, 1, 1)
    for inst in (a, b)
        fill_order!(acc, Order(oid!(acc), inst, dt_open, 10.0, 1.0); dt=dt_open, fill_price=10.0, bid=10.0, ask=10.0,
            last=10.0)
    end
    dt = dt_open + Day(1)
    for transfers in ([a => b], [a => a], [a => c, a => b], [a => c, b => c], [a => eur], [a => perp])
        @test_throws ArgumentError transfer_spot_positions!(acc, transfers, dt)
    end
    @test_throws ArgumentError transfer_spot_positions!(acc, [a => c], dt_open - Day(1))

    @test !acc.poisoned
    @test get_position(acc, a).quantity == 1.0
    @test get_position(acc, b).quantity == 1.0
    @test get_position(acc, c).quantity == 0.0
    @test acc.last_event_dt == dt_open
    @test Fastback.check_invariants(acc)

    transfer_spot_positions!(acc, [c => a], dt)
    @test get_position(acc, a).quantity == 1.0
    @test acc.last_event_dt == dt
end
