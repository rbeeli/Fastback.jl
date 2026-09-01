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
