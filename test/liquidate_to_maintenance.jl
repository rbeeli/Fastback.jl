using TestItemRunner

@testitem "liquidate_to_maintenance! closes largest maint contributor first" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
    deposit!(acc, :USD, 16_000.0)

    inst_big = register_instrument!(acc, InstrumentSpec(Symbol("BIG/USD"), :BIG, :USD;
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.2, margin_init_short=0.2,
        margin_maint_long=0.1, margin_maint_short=0.1))

    inst_small = register_instrument!(acc, InstrumentSpec(Symbol("SML/USD"), :SML, :USD;
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.2, margin_init_short=0.2,
        margin_maint_long=0.1, margin_maint_short=0.1))

    dt = DateTime(2024, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst_big, dt, 100.0, -50.0); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), inst_small, dt, 50.0, -10.0); dt=dt, fill_price=50.0, bid=50.0, ask=50.0, last=50.0)

    # Move against the short positions to trigger a maintenance breach
    dt2 = DateTime(2024, 1, 2)
    update_marks!(acc, get_position(acc, inst_big), dt2, 400.0, 400.0, 400.0)
    update_marks!(acc, get_position(acc, inst_small), dt2, 50.0, 50.0, 50.0)

    @test is_under_maintenance(acc)

    trades = liquidate_to_maintenance!(acc, dt2)

    @test !is_under_maintenance(acc)
    @test length(trades) == 1
    @test trades[1].order.inst === inst_big
    @test trades[1].reason == TradeReason.Liquidation
    @test get_position(acc, inst_big).quantity == 0.0
    @test get_position(acc, inst_small).quantity == -10.0
end

@testitem "liquidate_to_maintenance! applies broker commission" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; funding=AccountFunding.Margined, base_currency=base_currency, broker=FlatFeeBroker(fixed=1.0, pct=0.02))
    deposit!(acc, :USD, 1_500.0)

    inst = register_instrument!(acc, InstrumentSpec(Symbol("RISK/USD"), :RISK, :USD;
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1, margin_init_short=0.1,
        margin_maint_long=0.1, margin_maint_short=0.1))

    dt = DateTime(2024, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt, 100.0, 100.0); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    dt2 = dt + Day(1)
    update_marks!(acc, get_position(acc, inst), dt2, 90.0, 90.0, 90.0)

    # Account is under maintenance after an adverse mark.
    @test is_under_maintenance(acc)

    trades = liquidate_to_maintenance!(acc, dt2)

    @test length(trades) == 1
    @test trades[1].commission_settle ≈ 181.0 # 1 fixed + 2% of 90*100
    @test !is_under_maintenance(acc)
    @test get_position(acc, inst).quantity == 0.0
end

@testitem "base-currency liquidation uses projected option close improvement" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        margin_aggregation=MarginAggregation.BaseCurrency,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 15_050.0)

    dt = DateTime(2026, 1, 5)
    expiry = DateTime(2026, 2, 20)
    long_call = register_instrument!(acc, option_instrument(Symbol("BASELIQ_AAPL_C100"), :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    short_put_low = register_instrument!(acc, option_instrument(Symbol("BASELIQ_AAPL_P80"), :AAPL, :USD;
        strike=80.0,
        expiry=expiry,
        right=OptionRight.Put,
    ))
    short_put_high = register_instrument!(acc, option_instrument(Symbol("BASELIQ_AAPL_P110"), :AAPL, :USD;
        strike=110.0,
        expiry=expiry,
        right=OptionRight.Put,
    ))

    fill_option_strategy!(
        acc,
        [
            Order(oid!(acc), long_call, dt, 1.0, 1.0),
            Order(oid!(acc), short_put_low, dt, 10.0, -1.0),
            Order(oid!(acc), short_put_high, dt, 30.0, -1.0),
        ];
        dt=dt,
        fill_prices=[1.0, 10.0, 30.0],
        bids=[1.0, 10.0, 30.0],
        asks=[1.0, 10.0, 30.0],
        lasts=[1.0, 10.0, 30.0],
        underlying_price=100.0,
    )

    dt_stress = dt + Day(1)
    process_step!(
        acc,
        dt_stress;
        marks=[
            MarkUpdate(long_call.index, 1.0, 1.0, 1.0),
            MarkUpdate(short_put_low.index, 30.0, 30.0, 30.0),
            MarkUpdate(short_put_high.index, 150.0, 150.0, 150.0),
        ],
        option_underlyings=[OptionUnderlyingUpdate(:AAPL, :USD, 120.0)],
        expiries=false,
        liquidate=false,
        accrue_interest=false,
        accrue_borrow_fees=false,
    )

    current_excess = excess_liquidity_base_ccy(acc)
    @test current_excess ≈ -50.0 atol=1e-12
    @test is_under_maintenance(acc)
    @test Fastback._largest_maint_contributor(acc).inst === short_put_high
    @test Fastback._select_base_currency_liquidation_pos(acc, dt_stress, current_excess).inst === short_put_low
    @test Fastback._project_excess_base_after_full_close(acc, get_position(acc, short_put_high), dt_stress) < 0.0
    @test Fastback._project_excess_base_after_full_close(acc, get_position(acc, short_put_low), dt_stress) > 0.0

    trades = liquidate_to_maintenance!(acc, dt_stress)

    @test length(trades) == 1
    @test only(trades).order.inst === short_put_low
    @test get_position(acc, short_put_low).quantity == 0.0
    @test get_position(acc, short_put_high).quantity == -1.0
    @test get_position(acc, long_call).quantity == 1.0
    @test !is_under_maintenance(acc)
    @test Fastback.check_invariants(acc)
end

@testitem "maintenance liquidation force-closes residual option risk" begin
    using Test, Fastback, Dates

    function setup_residual_option_risk()
        acc = Account(;
            broker=NoOpBroker(),
            funding=AccountFunding.Margined,
            margin_aggregation=MarginAggregation.BaseCurrency,
            base_currency=CashSpec(:USD),
        )
        deposit!(acc, :USD, 13_300.0)

        dt = DateTime(2026, 1, 1)
        expiry = DateTime(2026, 2, 20)
        long_call = register_instrument!(acc, option_instrument(Symbol("MAINTBYPASS_AAPL_C120"), :AAPL, :USD;
            strike=120.0,
            expiry=expiry,
            right=OptionRight.Call,
        ))
        short_put_high = register_instrument!(acc, option_instrument(Symbol("MAINTBYPASS_AAPL_P130"), :AAPL, :USD;
            strike=130.0,
            expiry=expiry,
            right=OptionRight.Put,
        ))
        short_put_low = register_instrument!(acc, option_instrument(Symbol("MAINTBYPASS_AAPL_P70"), :AAPL, :USD;
            strike=70.0,
            expiry=expiry,
            right=OptionRight.Put,
        ))

        fill_option_strategy!(
            acc,
            [
                Order(oid!(acc), long_call, dt, 8.0, 1.0),
                Order(oid!(acc), short_put_high, dt, 20.0, -1.0),
                Order(oid!(acc), short_put_low, dt, 5.0, -1.0),
            ];
            dt=dt,
            fill_prices=[8.0, 20.0, 5.0],
            bids=[8.0, 20.0, 5.0],
            asks=[8.0, 20.0, 5.0],
            lasts=[8.0, 20.0, 5.0],
            underlying_price=100.0,
        )

        dt_stress = dt + Day(1)
        process_step!(
            acc,
            dt_stress;
            marks=[
                MarkUpdate(long_call.index, 64.0, 64.0, 64.0),
                MarkUpdate(short_put_high.index, 160.0, 160.0, 160.0),
                MarkUpdate(short_put_low.index, 20.0, 20.0, 20.0),
            ],
            option_underlyings=[OptionUnderlyingUpdate(:AAPL, :USD, 80.0)],
            expiries=false,
            liquidate=false,
            accrue_interest=false,
            accrue_borrow_fees=false,
        )

        acc, dt_stress, long_call, short_put_high, short_put_low
    end

    acc_regular, dt_stress, _, short_put_high_regular, short_put_low_regular = setup_residual_option_risk()
    @test is_under_maintenance(acc_regular)
    @test Fastback._select_base_currency_liquidation_pos(
        acc_regular,
        dt_stress,
        excess_liquidity_base_ccy(acc_regular),
    ).inst === short_put_low_regular
    fill_order!(acc_regular, Order(oid!(acc_regular), short_put_low_regular, dt_stress, 20.0, 1.0);
        dt=dt_stress,
        fill_price=20.0,
        bid=20.0,
        ask=20.0,
        last=20.0,
        trade_reason=TradeReason.Liquidation,
    )
    @test is_under_maintenance(acc_regular)
    @test Fastback._select_base_currency_liquidation_pos(
        acc_regular,
        dt_stress,
        excess_liquidity_base_ccy(acc_regular),
    ).inst === short_put_high_regular
    err = try
        fill_order!(acc_regular, Order(oid!(acc_regular), short_put_high_regular, dt_stress, 160.0, 1.0);
            dt=dt_stress,
            fill_price=160.0,
            bid=160.0,
            ask=160.0,
            last=160.0,
            trade_reason=TradeReason.Liquidation,
        )
        nothing
    catch e
        e
    end
    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin
    @test get_position(acc_regular, short_put_high_regular).quantity == -1.0

    acc, _, long_call, short_put_high, short_put_low = setup_residual_option_risk()
    trades = liquidate_to_maintenance!(acc, dt_stress)

    @test [t.order.inst for t in trades] == [short_put_low, short_put_high, long_call]
    @test all(t -> t.reason == TradeReason.Liquidation, trades)
    @test all(pos.quantity == 0.0 for pos in acc.positions)
    @test !is_under_maintenance(acc)
    @test excess_liquidity_base_ccy(acc) ≈ 3_400.0 atol=1e-10
    @test Fastback.check_invariants(acc)
end

@testitem "liquidate_to_maintenance! uses side-aware forced-close prices for variation margin" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, 25.0)

    inst = register_instrument!(acc, InstrumentSpec(Symbol("VMMAINT/USD"), :VMMAINT, :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1, margin_init_short=0.1,
        margin_maint_long=0.1, margin_maint_short=0.1))

    dt0 = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 101.0, 1.0); dt=dt0, fill_price=101.0, bid=99.0, ask=101.0, last=100.0)

    dt1 = dt0 + Hour(1)
    update_marks!(acc, inst, dt1, 79.0, 81.0, 80.0)
    @test is_under_maintenance(acc)

    trades = liquidate_to_maintenance!(acc, dt1)
    trade = only(trades)

    @test trade.fill_price ≈ 79.0 atol=1e-12
    @test trade.fill_pnl_settle ≈ -1.0 atol=1e-12
    @test trade.cash_delta_settle ≈ -1.0 atol=1e-12
    @test get_position(acc, inst).quantity == 0.0
    @test !is_under_maintenance(acc)
    @test Fastback.check_invariants(acc)
    @test maint_margin_used(acc, usd) ≈ 0.0 atol=1e-12
end

@testitem "per-currency liquidation targets offending currency" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency, margin_aggregation=MarginAggregation.PerCurrency, exchange_rates=er)

    deposit!(acc, :USD, 10_000.0)
    register_cash_asset!(acc, CashSpec(:EUR))
    deposit!(acc, :EUR, 200.0)
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.1)

    inst_eur = register_instrument!(acc, InstrumentSpec(Symbol("PER/EUR"), :PER, :EUR;
        settle_symbol=:EUR,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.3, margin_init_short=0.3,
        margin_maint_long=0.2, margin_maint_short=0.2))

    inst_usd = register_instrument!(acc, InstrumentSpec(Symbol("PER/USD"), :PER, :USD;
        settle_symbol=:USD,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.3, margin_init_short=0.3,
        margin_maint_long=0.2, margin_maint_short=0.2))

    dt = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst_eur, dt, 100.0, 5.0); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), inst_usd, dt, 100.0, 100.0); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    dt2 = dt + Hour(1)
    update_marks!(acc, inst_eur, dt2, 70.0, 70.0, 70.0)

    @test excess_liquidity(acc, cash_asset(acc, :EUR)) < 0 # only EUR leg is stressed
    @test is_under_maintenance(acc)

    trades = liquidate_to_maintenance!(acc, dt2)

    @test length(trades) == 1
    @test trades[1].order.inst === inst_eur
    @test !is_under_maintenance(acc)
    @test get_position(acc, inst_eur).quantity == 0.0
    @test get_position(acc, inst_usd).quantity == 100.0
    @test Fastback.check_invariants(acc)
end

@testitem "per-currency liquidation de-risks when worst currency has no margin-matched position" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency, margin_aggregation=MarginAggregation.PerCurrency, exchange_rates=er)
    register_cash_asset!(acc, CashSpec(:EUR))
    deposit!(acc, :USD, 0.0)
    deposit!(acc, :EUR, 1_000.0)
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.1) # EUR -> USD

    inst = register_instrument!(acc, InstrumentSpec(Symbol("PCUR/FALLBACK"), :PCUR, :USD;
        settle_symbol=:USD,
        margin_symbol=:EUR,
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=1.0,
        margin_init_short=1.0,
        margin_maint_long=0.5,
        margin_maint_short=0.5,
        multiplier=1.0,
    ))

    dt = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt, 100.0, 11.0); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    dt2 = dt + Hour(1)
    update_marks!(acc, inst, dt2, 50.0, 50.0, 50.0)

    # Deficit is in USD, while margin is tracked in EUR.
    @test excess_liquidity(acc, cash_asset(acc, :USD)) < 0
    @test is_under_maintenance(acc)

    err = try
        liquidate_to_maintenance!(acc, dt2)
        nothing
    catch e
        e
    end

    # Liquidation should de-risk open positions first (no immediate "wrong-currency" abort),
    # then fail only because no positions remain while equity is still negative.
    @test err isa ArgumentError
    @test get_position(acc, inst).quantity == 0.0
    @test count(t -> t.reason == TradeReason.Liquidation, acc.trades) == 1
end

@testitem "option spread liquidation projections use grouped maintenance" begin
    using Test, Fastback, Dates

    function setup_spread_account()
        acc = Account(;
            broker=NoOpBroker(),
            funding=AccountFunding.Margined,
            margin_aggregation=MarginAggregation.PerCurrency,
            base_currency=CashSpec(:USD),
        )
        usd = cash_asset(acc, :USD)
        deposit!(acc, :USD, 300.0)

        dt = DateTime(2026, 1, 5)
        expiry = DateTime(2026, 2, 20)
        spot = register_instrument!(acc, InstrumentSpec(Symbol("LIQSPOT/USD"), :LIQSPOT, :USD;
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.0,
            margin_init_short=0.0,
            margin_maint_long=0.0,
            margin_maint_short=0.0,
        ))
        long_call = register_instrument!(acc, option_instrument(Symbol("LIQ_AAPL_C105"), :AAPL, :USD;
            strike=105.0,
            expiry=expiry,
            right=OptionRight.Call,
        ))
        short_call = register_instrument!(acc, option_instrument(Symbol("LIQ_AAPL_C100"), :AAPL, :USD;
            strike=100.0,
            expiry=expiry,
            right=OptionRight.Call,
        ))

        fill_order!(acc, Order(oid!(acc), spot, dt, 100.0, 1.0);
            dt=dt,
            fill_price=100.0,
            bid=100.0,
            ask=100.0,
            last=100.0,
        )
        fill_option_strategy!(
            acc,
            [
                Order(oid!(acc), long_call, dt, 1.0, 1.0),
                Order(oid!(acc), short_call, dt, 3.0, -1.0),
            ];
            dt=dt,
            fill_prices=[1.0, 3.0],
            bids=[1.0, 3.0],
            asks=[1.0, 3.0],
            lasts=[1.0, 3.0],
            underlying_price=100.0,
        )

        dt_stress = dt + Day(1)
        process_step!(
            acc,
            dt_stress;
            marks=[
                MarkUpdate(spot.index, 50.0, 50.0, 50.0),
                MarkUpdate(long_call.index, 1.0, 1.0, 1.0),
                MarkUpdate(short_call.index, 3.0, 3.0, 3.0),
            ],
            option_underlyings=[OptionUnderlyingUpdate(:AAPL, :USD, 100.0)],
            expiries=false,
            liquidate=false,
            accrue_interest=false,
            accrue_borrow_fees=false,
        )

        acc, usd, spot, long_call, short_call, dt_stress
    end

    function apply_forced_close_without_risk!(acc, inst, dt)
        pos = get_position(acc, inst)
        pos_qty = pos.quantity
        fill_price, bid, ask = Fastback._forced_close_quotes(pos)
        close_qty = -pos_qty
        mark_for_valuation = Fastback._calc_mark_price(inst, pos_qty + close_qty, bid, ask)
        margin_price = Fastback.margin_reference_price(acc, inst, mark_for_valuation, pos.last_price)
        order = Order(oid!(acc), inst, dt, fill_price, close_qty)
        commission = broker_commission(acc.broker, inst, dt, close_qty, fill_price)
        plan = Fastback.plan_fill(
            acc,
            pos,
            order,
            dt,
            fill_price,
            mark_for_valuation,
            margin_price,
            close_qty,
            commission.fixed,
            commission.pct,
        )
        Fastback._apply_fill_plan!(
            acc,
            pos,
            order,
            dt,
            fill_price,
            bid,
            ask,
            pos.last_price,
            mark_for_valuation,
            plan,
            pos_qty,
            pos.avg_entry_price,
            TradeReason.Liquidation,
        )
        nothing
    end

    for pick in (:long, :short)
        acc_project, usd_project, _, long_project, short_project, dt_stress = setup_spread_account()
        inst_project = pick == :long ? long_project : short_project
        projected = Fastback._project_excess_after_full_close(
            acc_project,
            get_position(acc_project, inst_project),
            dt_stress,
            usd_project.index,
        )

        acc_actual, usd_actual, _, long_actual, short_actual, _ = setup_spread_account()
        apply_forced_close_without_risk!(acc_actual, pick == :long ? long_actual : short_actual, dt_stress)
        actual = excess_liquidity(acc_actual, usd_actual)

        @test projected ≈ actual atol=1e-12
        @test Fastback.check_invariants(acc_actual)
    end

    acc, usd, _, long_call, short_call, dt_stress = setup_spread_account()
    @test is_under_maintenance(acc)

    process_step!(
        acc,
        dt_stress + Hour(1);
        expiries=false,
        liquidate=true,
        accrue_interest=false,
        accrue_borrow_fees=false,
    )

    liquidation_trades = filter(t -> t.reason == TradeReason.Liquidation, acc.trades)
    @test length(liquidation_trades) == 1
    @test only(liquidation_trades).order.inst === short_call
    @test get_position(acc, short_call).quantity == 0.0
    @test get_position(acc, long_call).quantity == 1.0
    @test !is_under_maintenance(acc)
    @test excess_liquidity(acc, usd) ≈ 150.0 atol=1e-12
    @test Fastback.check_invariants(acc)
end
