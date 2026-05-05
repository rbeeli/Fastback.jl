using Dates
using TestItemRunner

@testitem "Option constructor validates listed option metadata" begin
    using Test, Fastback, Dates

    expiry = DateTime(2026, 1, 17)
    spec = option_instrument(Symbol("AAPL_20260117_C100"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    )

    @test Fastback.validate_instrument_spec(spec) === nothing
    @test spec.contract_kind == ContractKind.Option
    @test spec.settlement == SettlementStyle.PrincipalExchange
    @test spec.underlying_symbol == :AAPL
    @test spec.strike == 100.0
    @test spec.option_right == OptionRight.Call
    @test spec.exercise_style == OptionExerciseStyle.American
    @test spec.multiplier == 100.0
    @test spec.margin_requirement == MarginRequirement.PercentNotional
    @test spec.margin_init_long == 0.0
    @test spec.margin_init_short == 0.0
    @test spec.margin_maint_long == 0.0
    @test spec.margin_maint_short == 0.0
    @test spec.option_short_margin_rate == 0.20
    @test spec.option_short_margin_min_rate == 0.10
    @test spec.base_tick == 1.0
    @test spec.base_digits == 0

    inst = Instrument(1, 1, 1, 1, spec)
    @test option_intrinsic_value(inst, 112.5) == 12.5
    @test_throws ArgumentError option_intrinsic_value(inst, -1.0)
    @test has_expiry(inst)

    @test_throws ArgumentError option_instrument(Symbol("AAPL_NOEXP_C100"), :AAPL, :USD;
        strike=100.0,
        expiry=DateTime(0),
        right=OptionRight.Call,
    )
    @test_throws ArgumentError option_instrument(Symbol("AAPL_BADRIGHT"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Null,
    )
    @test_throws ArgumentError option_instrument(Symbol("AAPL_BADSTRIKE"), :AAPL, :USD;
        strike=0.0,
        expiry=expiry,
        right=OptionRight.Put,
    )
    @test_throws ArgumentError option_instrument(Symbol("AAPL_BADMARGIN"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Put,
        option_short_margin_rate=-0.01,
    )

    @test_throws MethodError option_instrument(Symbol("AAPL_GENERIC_MARGIN"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
        margin_init_long=0.10,
    )

    function direct_option_spec(;
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.0,
        margin_init_short=0.0,
        margin_maint_long=0.0,
        margin_maint_short=0.0,
    )
        InstrumentSpec(Symbol("AAPL_DIRECT_C100"), Symbol("AAPL_DIRECT_C100"), :USD;
            contract_kind=ContractKind.Option,
            settlement=SettlementStyle.PrincipalExchange,
            margin_requirement=margin_requirement,
            margin_init_long=margin_init_long,
            margin_init_short=margin_init_short,
            margin_maint_long=margin_maint_long,
            margin_maint_short=margin_maint_short,
            underlying_symbol=:AAPL,
            strike=100.0,
            option_right=OptionRight.Call,
            exercise_style=OptionExerciseStyle.American,
            expiry=expiry,
        )
    end

    @test Fastback.validate_instrument_spec(direct_option_spec()) === nothing
    @test_throws ArgumentError Fastback.validate_instrument_spec(direct_option_spec(;
        margin_requirement=MarginRequirement.FixedPerContract,
    ))
    @test_throws ArgumentError Fastback.validate_instrument_spec(direct_option_spec(;
        margin_init_long=0.10,
        margin_init_short=0.10,
    ))
end

@testitem "Option short margin rates are instrument-specific" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    expiry = DateTime(2026, 1, 17)
    put = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_P100_CUSTOM"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Put,
        option_short_margin_rate=0.15,
        option_short_margin_min_rate=0.05,
    ))

    update_option_underlying_price!(acc, put, 95.0)
    @test Fastback.margin_init_margin_ccy(acc, put, -1.0, 4.0) ≈ 1_825.0 atol=1e-12
end

@testitem "Option underlying marks are keyed by quote currency" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    register_cash_asset!(acc, CashSpec(:EUR))

    expiry = DateTime(2026, 1, 17)
    usd_call = register_instrument!(acc, option_instrument(Symbol("AAPL_USD_C100"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    eur_call = register_instrument!(acc, option_instrument(Symbol("AAPL_EUR_C100"), :AAPL, :EUR;
        strike=90.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    update_option_underlying_price!(acc, usd_call, 100.0)
    update_option_underlying_price!(acc, eur_call, 90.0)
    @test option_underlying_price(acc, usd_call) == 100.0
    @test option_underlying_price(acc, eur_call) == 90.0
    @test option_underlying_price(acc, :AAPL, :USD) == 100.0
    @test option_underlying_price(acc, :AAPL, :EUR) == 90.0
    @test_throws ArgumentError option_underlying_price(acc, :AAPL)
    @test_throws ArgumentError update_option_underlying_price!(acc, :AAPL, 101.0)

    process_step!(
        acc,
        DateTime(2026, 1, 6);
        option_underlyings=[
            OptionUnderlyingUpdate(usd_call, 101.0),
            OptionUnderlyingUpdate(:AAPL, :EUR, 91.0),
        ],
        expiries=false,
    )
    @test option_underlying_price(acc, usd_call) == 101.0
    @test option_underlying_price(acc, eur_call) == 91.0
end

@testitem "Long option premium and cash-settled expiry update cash and equity" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 10_000.0)

    expiry = DateTime(2026, 1, 17)
    call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C100"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    dt = DateTime(2026, 1, 5)
    fill_order!(acc, Order(oid!(acc), call, dt, 5.0, 2.0);
        dt=dt,
        fill_price=5.0,
        bid=5.0,
        ask=5.0,
        last=5.0,
    )

    pos = get_position(acc, call)
    @test cash_balance(acc, usd) ≈ 9_000.0 atol=1e-12
    @test equity(acc, usd) ≈ 10_000.0 atol=1e-12
    @test pos.value_quote ≈ 1_000.0 atol=1e-12
    @test init_margin_used(acc, usd) ≈ 1_000.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 1_000.0 atol=1e-12

    trade = settle_option_expiry!(acc, call, expiry; underlying_price=112.0)
    @test trade.reason == TradeReason.Expiry
    @test trade.fill_price == 12.0
    @test trade.cash_delta_settle ≈ 2_400.0 atol=1e-12
    @test trade.fill_pnl_settle ≈ 1_400.0 atol=1e-12
    @test get_position(acc, call).quantity == 0.0
    @test cash_balance(acc, usd) ≈ 11_400.0 atol=1e-12
    @test equity(acc, usd) ≈ 11_400.0 atol=1e-12
    @test Fastback.check_invariants(acc)
end

@testitem "Long option premium consumes buying power in margined accounts" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)

    expiry = DateTime(2026, 1, 17)
    call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C100_LONGMARGIN"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    dt = DateTime(2026, 1, 5)
    err = try
        fill_order!(acc, Order(oid!(acc), call, dt, 5.0, 10.0);
            dt=dt,
            fill_price=5.0,
            bid=5.0,
            ask=5.0,
            last=5.0,
        )
        nothing
    catch e
        e
    end

    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin
    @test cash_balance(acc, usd) == 0.0
    @test equity(acc, usd) == 0.0
    @test init_margin_used(acc, usd) == 0.0
    @test get_position(acc, call).quantity == 0.0

    deposit!(acc, :USD, 5_000.0)
    fill_order!(acc, Order(oid!(acc), call, dt, 5.0, 10.0);
        dt=dt,
        fill_price=5.0,
        bid=5.0,
        ask=5.0,
        last=5.0,
    )

    @test cash_balance(acc, usd) ≈ 0.0 atol=1e-12
    @test equity(acc, usd) ≈ 5_000.0 atol=1e-12
    @test init_margin_used(acc, usd) ≈ 5_000.0 atol=1e-12
    @test available_funds(acc, usd) ≈ 0.0 atol=1e-12
    @test Fastback.check_invariants(acc)
end

@testitem "Option fills, marks, and margin reject negative prices" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    deposit!(acc, :USD, 10_000.0)

    expiry = DateTime(2026, 1, 17)
    call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C100_NEGPRICE"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    dt = DateTime(2026, 1, 5)
    @test_throws ArgumentError update_marks!(acc, call, dt, -1.0, 1.0, 1.0)
    @test_throws ArgumentError update_marks!(acc, call, dt, 1.0, -1.0, 1.0)
    @test_throws ArgumentError update_marks!(acc, call, dt, 1.0, 1.0, -1.0)
    @test_throws ArgumentError process_step!(acc, dt;
        marks=[MarkUpdate(call.index, -1.0, 1.0, 1.0)],
        expiries=false,
    )

    @test_throws ArgumentError fill_order!(acc, Order(oid!(acc), call, dt, -1.0, 1.0);
        dt=dt,
        fill_price=-1.0,
        bid=1.0,
        ask=1.0,
        last=1.0,
    )
    @test_throws ArgumentError fill_order!(acc, Order(oid!(acc), call, dt, 1.0, 1.0);
        dt=dt,
        fill_price=1.0,
        bid=-1.0,
        ask=1.0,
        last=1.0,
    )
    @test_throws ArgumentError fill_order!(acc, Order(oid!(acc), call, dt, 1.0, 1.0);
        dt=dt,
        fill_price=1.0,
        bid=1.0,
        ask=-1.0,
        last=1.0,
    )
    @test_throws ArgumentError fill_order!(acc, Order(oid!(acc), call, dt, 1.0, 1.0);
        dt=dt,
        fill_price=1.0,
        bid=1.0,
        ask=1.0,
        last=-1.0,
    )

    @test_throws ArgumentError Fastback.margin_init_margin_ccy(acc, call, 1.0, -1.0)
    @test_throws ArgumentError Fastback.margin_maint_margin_ccy(acc, call, 1.0, -1.0)
    @test get_position(acc, call).quantity == 0.0
    @test Fastback.check_invariants(acc)
end

@testitem "Flat expired option does not require underlying mark" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))

    expiry = DateTime(2026, 1, 17)
    call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C100_FLAT"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    @test settle_option_expiry!(acc, call, expiry) === nothing
    @test process_step!(acc, expiry; expiries=true) === acc
    @test Fastback.check_invariants(acc)
end

@testitem "Short option margin uses underlying marks and option marks" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 10_000.0)

    expiry = DateTime(2026, 1, 17)
    put = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_P100"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Put,
    ))

    dt = DateTime(2026, 1, 5)
    fill_order!(acc, Order(oid!(acc), put, dt, 4.0, -1.0);
        dt=dt,
        fill_price=4.0,
        bid=4.0,
        ask=4.0,
        last=4.0,
        underlying_price=95.0,
    )

    @test cash_balance(acc, usd) ≈ 10_400.0 atol=1e-12
    @test equity(acc, usd) ≈ 10_000.0 atol=1e-12
    @test init_margin_used(acc, usd) ≈ 2_300.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 2_300.0 atol=1e-12

    process_step!(
        acc,
        dt + Day(1);
        option_underlyings=[OptionUnderlyingUpdate(:AAPL, :USD, 90.0)],
        marks=[MarkUpdate(put.index, 5.0, 5.0, 5.0)],
        expiries=false,
    )

    @test option_underlying_price(acc, :AAPL, :USD) == 90.0
    @test option_underlying_price(acc, put) == 90.0
    @test init_margin_used(acc, usd) ≈ 2_300.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 2_300.0 atol=1e-12
    @test Fastback.check_invariants(acc)
end

@testitem "Underlying update refreshes every option sharing the chain symbol" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 10_000.0)

    expiry = DateTime(2026, 1, 17)
    put100 = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_P100_CHAIN"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Put,
    ))
    put90 = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_P90_CHAIN"), :AAPL, :USD;
        strike=90.0,
        expiry=expiry,
        right=OptionRight.Put,
    ))

    dt = DateTime(2026, 1, 5)
    fill_order!(acc, Order(oid!(acc), put100, dt, 4.0, -1.0);
        dt=dt,
        fill_price=4.0,
        bid=4.0,
        ask=4.0,
        last=4.0,
        underlying_price=95.0,
    )
    fill_order!(acc, Order(oid!(acc), put90, dt, 2.0, -1.0);
        dt=dt,
        fill_price=2.0,
        bid=2.0,
        ask=2.0,
        last=2.0,
    )

    @test option_underlying_price(acc, put100) == 95.0
    @test option_underlying_price(acc, put90) == 95.0
    @test init_margin_used(acc, usd) ≈ 3_900.0 atol=1e-12

    process_step!(
        acc,
        dt + Day(1);
        option_underlyings=[OptionUnderlyingUpdate(:AAPL, :USD, 90.0)],
        marks=[
            MarkUpdate(put100.index, 5.0, 5.0, 5.0),
            MarkUpdate(put90.index, 3.0, 3.0, 3.0),
        ],
        expiries=false,
    )

    @test option_underlying_price(acc, put100) == 90.0
    @test option_underlying_price(acc, put90) == 90.0
    @test init_margin_used(acc, usd) ≈ 4_400.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 4_400.0 atol=1e-12
    @test Fastback.check_invariants(acc)
end

@testitem "Vertical option spread caps short margin and protects long leg closes" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000.0)

    expiry = DateTime(2026, 1, 17)
    short_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C100"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    long_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C105"), :AAPL, :USD;
        strike=105.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    dt = DateTime(2026, 1, 5)
    fill_order!(acc, Order(oid!(acc), long_call, dt, 1.0, 1.0);
        dt=dt,
        fill_price=1.0,
        bid=1.0,
        ask=1.0,
        last=1.0,
    )

    fill_order!(acc, Order(oid!(acc), short_call, dt, 3.0, -1.0);
        dt=dt,
        fill_price=3.0,
        bid=3.0,
        ask=3.0,
        last=3.0,
        underlying_price=100.0,
    )

    @test equity(acc, usd) ≈ 1_000.0 atol=1e-12
    @test init_margin_used(acc, usd) ≈ 300.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 300.0 atol=1e-12

    long_pos = get_position(acc, long_call)
    short_pos = get_position(acc, short_call)
    before = (
        cash=cash_balance(acc, usd),
        equity=equity(acc, usd),
        init=init_margin_used(acc, usd),
        maint=maint_margin_used(acc, usd),
        long_mark=long_pos.mark_price,
        long_value=long_pos.value_settle,
        long_pnl=long_pos.pnl_settle,
        long_init=long_pos.init_margin_settle,
        long_maint=long_pos.maint_margin_settle,
        long_bid=long_pos.last_bid,
        long_ask=long_pos.last_ask,
        long_last=long_pos.last_price,
        long_mark_time=long_pos.mark_time,
        short_init=short_pos.init_margin_settle,
        short_maint=short_pos.maint_margin_settle,
        underlying=option_underlying_price(acc, :AAPL, :USD),
        trades=length(acc.trades),
        trade_sequence=acc.trade_sequence,
        trade_count=acc.trade_count,
    )

    err = try
        fill_order!(acc, Order(oid!(acc), long_call, dt + Hour(1), 1.2, -1.0);
            dt=dt + Hour(1),
            fill_price=1.2,
            bid=1.2,
            ask=1.2,
            last=1.2,
            underlying_price=99.0,
        )
        nothing
    catch e
        e
    end

    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin
    @test cash_balance(acc, usd) ≈ before.cash atol=1e-12
    @test equity(acc, usd) ≈ before.equity atol=1e-12
    @test init_margin_used(acc, usd) ≈ before.init atol=1e-12
    @test maint_margin_used(acc, usd) ≈ before.maint atol=1e-12
    @test long_pos.quantity == 1.0
    @test long_pos.mark_price == before.long_mark
    @test long_pos.value_settle == before.long_value
    @test long_pos.pnl_settle == before.long_pnl
    @test long_pos.init_margin_settle == before.long_init
    @test long_pos.maint_margin_settle == before.long_maint
    @test long_pos.last_bid == before.long_bid
    @test long_pos.last_ask == before.long_ask
    @test long_pos.last_price == before.long_last
    @test long_pos.mark_time == before.long_mark_time
    @test short_pos.quantity == -1.0
    @test short_pos.init_margin_settle == before.short_init
    @test short_pos.maint_margin_settle == before.short_maint
    @test option_underlying_price(acc, :AAPL, :USD) == before.underlying
    @test length(acc.trades) == before.trades
    @test acc.trade_sequence == before.trade_sequence
    @test acc.trade_count == before.trade_count
    @test Fastback.check_invariants(acc)
end

@testitem "Debit vertical option spread caps short margin by strike width" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000.0)

    expiry = DateTime(2026, 1, 17)
    long_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C100_DEBIT"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    short_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C105_DEBIT"), :AAPL, :USD;
        strike=105.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    dt = DateTime(2026, 1, 5)
    fill_order!(acc, Order(oid!(acc), long_call, dt, 5.0, 1.0);
        dt=dt,
        fill_price=5.0,
        bid=5.0,
        ask=5.0,
        last=5.0,
    )

    fill_order!(acc, Order(oid!(acc), short_call, dt, 2.0, -1.0);
        dt=dt,
        fill_price=2.0,
        bid=2.0,
        ask=2.0,
        last=2.0,
        underlying_price=100.0,
    )

    @test equity(acc, usd) ≈ 1_000.0 atol=1e-12
    @test cash_balance(acc, usd) ≈ 700.0 atol=1e-12
    @test init_margin_used(acc, usd) ≈ 300.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 300.0 atol=1e-12
    @test Fastback.check_invariants(acc)
end

@testitem "Atomic option strategy fill checks final package margin" begin
    using Test, Fastback, Dates

    dt = DateTime(2026, 1, 5)
    expiry = DateTime(2026, 1, 17)

    acc_single = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd_single = cash_asset(acc_single, :USD)
    deposit!(acc_single, :USD, 300.0)
    single_long = register_instrument!(acc_single, option_instrument(Symbol("AAPL_20260117_C100_SINGLE"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    err = try
        fill_order!(acc_single, Order(oid!(acc_single), single_long, dt, 5.0, 1.0);
            dt=dt,
            fill_price=5.0,
            bid=5.0,
            ask=5.0,
            last=5.0,
        )
        nothing
    catch e
        e
    end
    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin
    @test cash_balance(acc_single, usd_single) ≈ 300.0 atol=1e-12
    @test get_position(acc_single, single_long).quantity == 0.0

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 300.0)
    long_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C100_BATCH"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    short_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C105_BATCH"), :AAPL, :USD;
        strike=105.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    trades = fill_option_strategy!(
        acc,
        [
            Order(oid!(acc), long_call, dt, 5.0, 1.0),
            Order(oid!(acc), short_call, dt, 2.0, -1.0),
        ];
        dt=dt,
        fill_prices=[5.0, 2.0],
        bids=[5.0, 2.0],
        asks=[5.0, 2.0],
        lasts=[5.0, 2.0],
        underlying_price=100.0,
    )

    @test length(trades) == 2
    @test eltype(trades) === Trade{DateTime}
    @test cash_balance(acc, usd) ≈ 0.0 atol=1e-12
    @test equity(acc, usd) ≈ 300.0 atol=1e-12
    @test init_margin_used(acc, usd) ≈ 300.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 300.0 atol=1e-12
    @test available_funds(acc, usd) ≈ 0.0 atol=1e-12
    @test Fastback.check_invariants(acc)

    acc_fail = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd_fail = cash_asset(acc_fail, :USD)
    deposit!(acc_fail, :USD, 299.0)
    fail_long = register_instrument!(acc_fail, option_instrument(Symbol("AAPL_20260117_C100_BATCH_FAIL"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    fail_short = register_instrument!(acc_fail, option_instrument(Symbol("AAPL_20260117_C105_BATCH_FAIL"), :AAPL, :USD;
        strike=105.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    err = try
        fill_option_strategy!(
            acc_fail,
            [
                Order(oid!(acc_fail), fail_long, dt, 5.0, 1.0),
                Order(oid!(acc_fail), fail_short, dt, 2.0, -1.0),
            ];
            dt=dt,
            fill_prices=[5.0, 2.0],
            bids=[5.0, 2.0],
            asks=[5.0, 2.0],
            lasts=[5.0, 2.0],
            underlying_price=100.0,
        )
        nothing
    catch e
        e
    end
    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin
    @test cash_balance(acc_fail, usd_fail) ≈ 299.0 atol=1e-12
    @test get_position(acc_fail, fail_long).quantity == 0.0
    @test get_position(acc_fail, fail_short).quantity == 0.0
    @test isempty(acc_fail.trades)
    @test Fastback.check_invariants(acc_fail)
end

@testitem "fill_option_strategy! can price IBKR option package commission once" begin
    using Test, Fastback, Dates

    dt = DateTime(2026, 1, 5)
    expiry = DateTime(2026, 1, 17)
    package_broker = IBKRProFixedBroker(;
        option_orf_per_contract=0.0,
        option_occ_per_contract=0.0,
        option_cat_per_contract=0.0,
        option_finra_taf_per_contract_sold=0.0,
        option_sec_transaction_rate=0.0,
    )
    per_leg_broker = IBKRProFixedBroker(;
        option_orf_per_contract=0.0,
        option_occ_per_contract=0.0,
        option_cat_per_contract=0.0,
        option_finra_taf_per_contract_sold=0.0,
        option_sec_transaction_rate=0.0,
        option_strategy_commission=OptionStrategyCommissionMode.PerLegOrders,
    )

    function make_account(tag::Symbol, account_broker)
        acc = Account(; broker=account_broker, funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
        usd = cash_asset(acc, :USD)
        deposit!(acc, :USD, 1_000.0)
        long_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C100_$(tag)"), :AAPL, :USD;
            strike=100.0,
            expiry=expiry,
            right=OptionRight.Call,
        ))
        short_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C105_$(tag)"), :AAPL, :USD;
            strike=105.0,
            expiry=expiry,
            right=OptionRight.Call,
        ))
        acc, usd, long_call, short_call
    end

    acc_pkg, usd_pkg, pkg_long, pkg_short = make_account(:COMBO_PACKAGE, package_broker)
    trades_pkg = fill_option_strategy!(
        acc_pkg,
        [
            Order(oid!(acc_pkg), pkg_long, dt, 0.04, 1.0),
            Order(oid!(acc_pkg), pkg_short, dt, 0.03, -1.0),
        ];
        dt=dt,
        fill_prices=[0.04, 0.03],
        bids=[0.04, 0.03],
        asks=[0.04, 0.03],
        lasts=[0.04, 0.03],
        underlying_price=100.0,
    )

    acc_leg, usd_leg, leg_long, leg_short = make_account(:COMBO_LEGS, per_leg_broker)
    trades_leg = fill_option_strategy!(
        acc_leg,
        [
            Order(oid!(acc_leg), leg_long, dt, 0.04, 1.0),
            Order(oid!(acc_leg), leg_short, dt, 0.03, -1.0),
        ];
        dt=dt,
        fill_prices=[0.04, 0.03],
        bids=[0.04, 0.03],
        asks=[0.04, 0.03],
        lasts=[0.04, 0.03],
        underlying_price=100.0,
    )

    @test sum(t.commission_quote for t in trades_pkg) ≈ 1.0 atol=1e-12
    @test sum(t.commission_quote for t in trades_leg) ≈ 2.0 atol=1e-12
    @test cash_balance(acc_pkg, usd_pkg) ≈ 998.0 atol=1e-12
    @test cash_balance(acc_leg, usd_leg) ≈ 997.0 atol=1e-12
    @test Fastback.check_invariants(acc_pkg)
    @test Fastback.check_invariants(acc_leg)
end

@testitem "Rejected option strategy fill restores preflight mark and margin state" begin
    using Test, Fastback, Dates

    dt = DateTime(2026, 1, 5)
    expiry = DateTime(2026, 1, 17)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000.0)

    long_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C100_REJECT_RESTORE"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    other_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C110_REJECT_RESTORE"), :AAPL, :USD;
        strike=110.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    fill_order!(acc, Order(oid!(acc), long_call, dt, 5.0, 1.0);
        dt=dt,
        fill_price=5.0,
        bid=5.0,
        ask=5.0,
        last=5.0,
        underlying_price=100.0,
    )

    pos = get_position(acc, long_call)
    flat_pos = get_position(acc, other_call)
    before = (
        cash=cash_balance(acc, usd),
        equity=equity(acc, usd),
        init=init_margin_used(acc, usd),
        maint=maint_margin_used(acc, usd),
        mark=pos.mark_price,
        value=pos.value_settle,
        pnl=pos.pnl_settle,
        pos_init=pos.init_margin_settle,
        pos_maint=pos.maint_margin_settle,
        mark_time=pos.mark_time,
        underlying=option_underlying_price(acc, :AAPL, :USD),
        trades=length(acc.trades),
        trade_sequence=acc.trade_sequence,
        trade_count=acc.trade_count,
    )

    err = try
        fill_option_strategy!(
            acc,
            [
                Order(oid!(acc), long_call, dt + Day(1), 4.0, -1.0),
                Order(oid!(acc), other_call, dt + Day(1), 20.0, 1.0),
            ];
            dt=dt + Day(1),
            fill_prices=[4.0, 20.0],
            bids=[4.0, 20.0],
            asks=[4.0, 20.0],
            lasts=[4.0, 20.0],
            underlying_price=99.0,
        )
        nothing
    catch e
        e
    end

    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin
    @test cash_balance(acc, usd) ≈ before.cash atol=1e-12
    @test equity(acc, usd) ≈ before.equity atol=1e-12
    @test init_margin_used(acc, usd) ≈ before.init atol=1e-12
    @test maint_margin_used(acc, usd) ≈ before.maint atol=1e-12
    @test pos.quantity == 1.0
    @test pos.mark_price == before.mark
    @test pos.value_settle == before.value
    @test pos.pnl_settle == before.pnl
    @test pos.init_margin_settle == before.pos_init
    @test pos.maint_margin_settle == before.pos_maint
    @test pos.mark_time == before.mark_time
    @test option_underlying_price(acc, :AAPL, :USD) == before.underlying
    @test flat_pos.quantity == 0.0
    @test isnan(flat_pos.mark_price)
    @test length(acc.trades) == before.trades
    @test acc.trade_sequence == before.trade_sequence
    @test acc.trade_count == before.trade_count
    @test Fastback.check_invariants(acc)
end

@testitem "Iron condor margin uses mutually exclusive terminal risk" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_200.0)

    expiry = DateTime(2026, 1, 17)
    long_put = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_P90_CONDOR"), :AAPL, :USD;
        strike=90.0,
        expiry=expiry,
        right=OptionRight.Put,
    ))
    short_put = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_P100_CONDOR"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Put,
    ))
    short_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C110_CONDOR"), :AAPL, :USD;
        strike=110.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    long_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C120_CONDOR"), :AAPL, :USD;
        strike=120.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    dt = DateTime(2026, 1, 5)
    fill_order!(acc, Order(oid!(acc), long_put, dt, 1.0, 1.0);
        dt=dt,
        fill_price=1.0,
        bid=1.0,
        ask=1.0,
        last=1.0,
    )
    fill_order!(acc, Order(oid!(acc), short_put, dt, 3.0, -1.0);
        dt=dt,
        fill_price=3.0,
        bid=3.0,
        ask=3.0,
        last=3.0,
        underlying_price=105.0,
    )
    fill_order!(acc, Order(oid!(acc), long_call, dt, 1.0, 1.0);
        dt=dt,
        fill_price=1.0,
        bid=1.0,
        ask=1.0,
        last=1.0,
    )
    fill_order!(acc, Order(oid!(acc), short_call, dt, 3.0, -1.0);
        dt=dt,
        fill_price=3.0,
        bid=3.0,
        ask=3.0,
        last=3.0,
        underlying_price=105.0,
    )

    @test equity(acc, usd) ≈ 1_200.0 atol=1e-12
    @test cash_balance(acc, usd) ≈ 1_600.0 atol=1e-12
    @test init_margin_used(acc, usd) ≈ 600.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 600.0 atol=1e-12
    @test available_funds(acc, usd) ≈ 600.0 atol=1e-12
    @test Fastback.check_invariants(acc)
end

@testitem "Butterfly margin uses net debit terminal risk" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000.0)

    expiry = DateTime(2026, 1, 17)
    long_lower = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C100_FLY"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    short_mid = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C105_FLY"), :AAPL, :USD;
        strike=105.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    long_upper = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C110_FLY"), :AAPL, :USD;
        strike=110.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    dt = DateTime(2026, 1, 5)
    fill_order!(acc, Order(oid!(acc), long_lower, dt, 7.0, 1.0);
        dt=dt,
        fill_price=7.0,
        bid=7.0,
        ask=7.0,
        last=7.0,
    )
    fill_order!(acc, Order(oid!(acc), long_upper, dt, 2.0, 1.0);
        dt=dt,
        fill_price=2.0,
        bid=2.0,
        ask=2.0,
        last=2.0,
    )
    fill_order!(acc, Order(oid!(acc), short_mid, dt, 4.0, -2.0);
        dt=dt,
        fill_price=4.0,
        bid=4.0,
        ask=4.0,
        last=4.0,
        underlying_price=105.0,
    )

    @test equity(acc, usd) ≈ 1_000.0 atol=1e-12
    @test cash_balance(acc, usd) ≈ 900.0 atol=1e-12
    @test init_margin_used(acc, usd) ≈ 100.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 100.0 atol=1e-12
    @test Fastback.check_invariants(acc)
end

@testitem "Cached option margins match slow reference after batched dirty recompute" begin
    using Test, Fastback, Dates, Random

    rng = MersenneTwister(7)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 1_000_000.0)

    dt = DateTime(2026, 1, 5)
    expiry = DateTime(2026, 2, 20)
    insts = Instrument{DateTime}[]
    for (right, strikes) in ((OptionRight.Put, [90.0, 100.0]), (OptionRight.Call, [105.0, 115.0]))
        for strike in strikes
            push!(insts, register_instrument!(acc, option_instrument(Symbol("CACHE_$(right)_$(Int(strike))"), :AAPL, :USD;
                strike=strike,
                expiry=expiry,
                right=right,
            )))
        end
    end

    for inst in insts
        px = Price(rand(rng, 1:6))
        qty = rand(rng, [-2.0, -1.0, 1.0, 2.0])
        fill_order!(acc, Order(oid!(acc), inst, dt, px, qty);
            dt=dt,
            fill_price=px,
            bid=px,
            ask=px,
            last=px,
            underlying_price=104.0,
        )
    end

    marks = [MarkUpdate(inst.index, Price(rand(rng, 1:8)), Price(rand(rng, 1:8)), Price(rand(rng, 1:8))) for inst in insts]
    process_step!(
        acc,
        dt + Day(1);
        option_underlyings=[OptionUnderlyingUpdate(:AAPL, :USD, 101.0)],
        marks=marks,
        expiries=false,
        accrue_interest=false,
        accrue_borrow_fees=false,
    )

    fast_init = copy(acc.ledger.init_margin_used)
    fast_maint = copy(acc.ledger.maint_margin_used)
    fast_option_init = copy(acc.option_init_by_cash)
    fast_option_maint = copy(acc.option_maint_by_cash)
    fast_pos_init = [pos.init_margin_settle for pos in acc.positions]
    fast_pos_maint = [pos.maint_margin_settle for pos in acc.positions]

    Fastback.recompute_option_margins_slow!(acc)

    @test acc.ledger.init_margin_used ≈ fast_init atol=1e-9
    @test acc.ledger.maint_margin_used ≈ fast_maint atol=1e-9
    @test acc.option_init_by_cash ≈ fast_option_init atol=1e-9
    @test acc.option_maint_by_cash ≈ fast_option_maint atol=1e-9
    @test [pos.init_margin_settle for pos in acc.positions] ≈ fast_pos_init atol=1e-9
    @test [pos.maint_margin_settle for pos in acc.positions] ≈ fast_pos_maint atol=1e-9
    @test init_margin_used(acc, usd) ≈ fast_init[usd.index] atol=1e-9
    @test Fastback.check_invariants(acc)
end

@testitem "FX update refreshes option quote-to-margin cache" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        margin_aggregation=MarginAggregation.PerCurrency,
        base_currency=CashSpec(:USD),
    )
    usd = cash_asset(acc, :USD)
    eur = register_cash_asset!(acc, CashSpec(:EUR))
    update_rate!(acc.exchange_rates, usd, eur, 1.0)
    deposit!(acc, :EUR, 10_000.0)

    expiry = DateTime(2026, 1, 17)
    call = register_instrument!(acc, option_instrument(Symbol("AAPL_USD_MARGIN_EUR_C100"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
        margin_symbol=:EUR,
    ))

    dt = DateTime(2026, 1, 5)
    fill_order!(acc, Order(oid!(acc), call, dt, 3.0, -1.0);
        dt=dt,
        fill_price=3.0,
        bid=3.0,
        ask=3.0,
        last=3.0,
        underlying_price=100.0,
    )
    @test init_margin_used(acc, eur) ≈ 2_300.0 atol=1e-12
    @test acc.option_init_by_cash[eur.index] ≈ 2_300.0 atol=1e-12

    process_step!(
        acc,
        dt + Day(1);
        fx_updates=[FXUpdate(usd, eur, 0.5)],
        expiries=false,
        accrue_interest=false,
        accrue_borrow_fees=false,
    )

    @test init_margin_used(acc, eur) ≈ 1_150.0 atol=1e-12
    @test maint_margin_used(acc, eur) ≈ 1_150.0 atol=1e-12
    @test acc.option_init_by_cash[eur.index] ≈ 1_150.0 atol=1e-12
    @test acc.option_maint_by_cash[eur.index] ≈ 1_150.0 atol=1e-12
    @test Fastback.check_invariants(acc)
end

@testitem "Batched option mark dirty tracking deduplicates groups" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    deposit!(acc, :USD, 10_000.0)

    expiry = DateTime(2026, 1, 17)
    long_call = register_instrument!(acc, option_instrument(Symbol("DEDUP_C100"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    short_call = register_instrument!(acc, option_instrument(Symbol("DEDUP_C105"), :AAPL, :USD;
        strike=105.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    dt = DateTime(2026, 1, 5)
    fill_option_strategy!(
        acc,
        [Order(oid!(acc), long_call, dt, 5.0, 1.0), Order(oid!(acc), short_call, dt, 2.0, -1.0)];
        dt=dt,
        fill_prices=[5.0, 2.0],
        bids=[5.0, 2.0],
        asks=[5.0, 2.0],
        lasts=[5.0, 2.0],
        underlying_price=100.0,
    )

    Fastback._update_marks_from_quotes!(acc, get_position(acc, long_call), dt + Day(1), 4.0, 4.0, 4.0, false)
    Fastback.mark_option_position_dirty!(acc, long_call.index)
    Fastback._update_marks_from_quotes!(acc, get_position(acc, short_call), dt + Day(1), 1.5, 1.5, 1.5, false)
    Fastback.mark_option_position_dirty!(acc, short_call.index)

    @test length(acc.dirty_option_groups) == 1
    Fastback.recompute_dirty_option_groups!(acc)
    @test isempty(acc.dirty_option_groups)
    @test Fastback.check_invariants(acc)
end

@testitem "Option margin groups track sparse active positions" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 20_000.0)

    dt = DateTime(2026, 1, 5)
    expiry = DateTime(2026, 1, 17)
    chain = Instrument[]
    for strike in 80.0:5.0:140.0
        push!(chain, register_instrument!(acc, option_instrument(Symbol("SPARSE_C$(Int(strike))"), :AAPL, :USD;
            strike=strike,
            expiry=expiry,
            right=OptionRight.Call,
        )))
    end
    inactive_expiry_call = register_instrument!(acc, option_instrument(Symbol("SPARSE_NEXT_C100"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry + Day(7),
        right=OptionRight.Call,
    ))

    long_call = chain[5]   # C100
    short_call = chain[6]  # C105
    group_id = acc.option_group_id_by_pos[long_call.index]
    group = acc.option_groups[group_id]
    inactive_group_id = acc.option_group_id_by_pos[inactive_expiry_call.index]

    @test length(group.positions) == length(chain)
    @test length(group.sorted_positions) == length(chain)
    @test isempty(group.active_positions)
    @test isempty(group.sorted_active_positions)
    @test sort(acc.option_group_ids_by_underlying[(:AAPL, :USD)]) == sort([group_id, inactive_group_id])

    fill_option_strategy!(
        acc,
        [
            Order(oid!(acc), long_call, dt, 5.0, 1.0),
            Order(oid!(acc), short_call, dt, 2.0, -1.0),
        ];
        dt=dt,
        fill_prices=[5.0, 2.0],
        bids=[5.0, 2.0],
        asks=[5.0, 2.0],
        lasts=[5.0, 2.0],
        underlying_price=100.0,
    )

    @test sort(group.active_positions) == sort([long_call.index, short_call.index])
    @test group.sorted_active_positions == [long_call.index, short_call.index]
    @test acc.option_position_active[long_call.index]
    @test acc.option_position_active[short_call.index]
    @test !acc.option_position_active[inactive_expiry_call.index]
    @test init_margin_used(acc, usd) ≈ 300.0 atol=1e-12

    Fastback.mark_option_underlying_dirty!(acc, :AAPL, :USD)
    @test acc.dirty_option_groups == [group_id]
    Fastback.recompute_dirty_option_groups!(acc)
    @test isempty(acc.dirty_option_groups)

    fill_order!(acc, Order(oid!(acc), short_call, dt + Hour(1), 2.0, 1.0);
        dt=dt + Hour(1),
        fill_price=2.0,
        bid=2.0,
        ask=2.0,
        last=2.0,
        underlying_price=100.0,
    )

    @test group.active_positions == [long_call.index]
    @test group.sorted_active_positions == [long_call.index]
    @test !acc.option_position_active[short_call.index]

    fill_order!(acc, Order(oid!(acc), long_call, dt + Hour(2), 5.0, -1.0);
        dt=dt + Hour(2),
        fill_price=5.0,
        bid=5.0,
        ask=5.0,
        last=5.0,
    )

    @test isempty(group.active_positions)
    @test isempty(group.sorted_active_positions)
    @test !acc.option_position_active[long_call.index]
    @test init_margin_used(acc, usd) ≈ 0.0 atol=1e-12
    @test maint_margin_used(acc, usd) ≈ 0.0 atol=1e-12

    Fastback.mark_option_underlying_dirty!(acc, :AAPL, :USD)
    @test isempty(acc.dirty_option_groups)
    @test Fastback.check_invariants(acc)
end
