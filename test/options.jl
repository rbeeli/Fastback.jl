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

    err = try
        fill_order!(acc, Order(oid!(acc), long_call, dt + Hour(1), 1.0, -1.0);
            dt=dt + Hour(1),
            fill_price=1.0,
            bid=1.0,
            ask=1.0,
            last=1.0,
        )
        nothing
    catch e
        e
    end

    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin
    @test get_position(acc, long_call).quantity == 1.0
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
    @test all(!isnothing, trades)
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
