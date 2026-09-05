using TestItemRunner

@testitem "target-weight portfolio rebalances from stored top-of-book quotes" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 1_000.0)
    inst = register_instrument!(acc, spot_instrument(
        Symbol("PORT/USD"),
        :PORT,
        :USD;
        base_tick=1.0,
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))
    dt = DateTime(2028, 1, 2)
    update_marks!(acc, inst, dt, 99.0, 101.0, 100.0)

    portfolio = Portfolio(acc)
    result = rebalance!(portfolio, dt, TargetWeights(inst => 0.5))

    trade = only(result.trades)
    @test trade.order.inst === inst
    @test trade.fill_qty == 5.0
    @test trade.fill_price == 101.0
    @test isempty(result.suppressed)
    @test result.pretrade.equity == 1_000.0
    @test result.posttrade.equity == 990.0
    @test get_position(acc, inst).quantity == 5.0

    exposure = portfolio_exposure(portfolio)
    @test exposure.snapshot == result.posttrade
    @test exposure.gross_notional == 495.0
    @test exposure.net_notional == 495.0
    @test Fastback.check_invariants(acc)
end

@testitem "target validation and zero-weight membership are explicit" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 1_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("ZERO/USD"), :ZERO, :USD))

    @test_throws ArgumentError TargetWeights([inst => 0.1, inst => 0.2])
    @test_throws ArgumentError TargetWeights(inst => NaN)
    @test_throws ArgumentError TargetWeights(0 => 0.1)
    @test_throws ArgumentError RebalancePolicy(minimum_notional_base=-1.0)
    @test_throws ArgumentError SpreadFillModel(full_spread_basis_points=Inf)

    mutated = TargetWeights(inst => 0.0)
    mutated.weights[1] = inst.index => NaN
    @test_throws ArgumentError rebalance!(Portfolio(acc), DateTime(2028, 1, 2), mutated)

    dt = DateTime(2028, 1, 2)
    result = rebalance!(Portfolio(acc), dt, TargetWeights(inst => 0.0))
    @test isempty(result.trades)
    @test isempty(result.suppressed)
    @test acc.last_event_dt == DateTime(0)
end

@testitem "rebalance policies suppress dust but never full exits" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 1_000.0)
    inst = register_instrument!(acc, spot_instrument(
        Symbol("POLICY/USD"),
        :POLICY,
        :USD;
        base_tick=0.1,
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))
    dt = DateTime(2028, 1, 2)
    update_marks!(acc, inst, dt, 100.0, 100.0, 100.0)
    portfolio = Portfolio(acc)
    policy = RebalancePolicy(minimum_notional_base=100.0)

    suppressed = rebalance!(portfolio, dt, TargetWeights(inst => 0.05); policy=policy)
    @test isempty(suppressed.trades)
    @test suppressed.suppressed == [inst.index]
    @test get_position(acc, inst).quantity == 0.0

    fill_order!(
        acc,
        Order(oid!(acc), inst, dt, 100.0, 1.0);
        dt=dt,
        fill_price=100.0,
        bid=100.0,
        ask=100.0,
        last=100.0,
    )
    trade_count = length(acc.trades)
    @test_throws ArgumentError rebalance!(
        portfolio,
        dt,
        TargetWeights();
        policy=RebalancePolicy(orphan_positions=OrphanPositionPolicy.Reject),
    )
    @test length(acc.trades) == trade_count
    @test get_position(acc, inst).quantity == 1.0

    exited = rebalance!(portfolio, dt, TargetWeights(); policy=policy)
    @test length(exited.trades) == 1
    @test exited.trades[1].fill_qty == -1.0
    @test isempty(exited.suppressed)
    @test get_position(acc, inst).quantity == 0.0
end

@testitem "fully funded portfolio scales buys uniformly after reductions" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.FullyFunded,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 100.0)
    first_inst = register_instrument!(acc, spot_instrument(
        Symbol("SCALEA/USD"),
        :SCALEA,
        :USD;
        base_tick=0.1,
    ))
    second_inst = register_instrument!(acc, spot_instrument(
        Symbol("SCALEB/USD"),
        :SCALEB,
        :USD;
        base_tick=0.1,
    ))
    dt = DateTime(2028, 1, 2)
    update_marks!(acc, first_inst, dt, 40.0, 60.0, 50.0)
    update_marks!(acc, second_inst, dt, 40.0, 60.0, 50.0)

    result = rebalance!(
        Portfolio(acc),
        dt,
        TargetWeights(first_inst => 1.0, second_inst => 1.0),
    )
    @test get_position(acc, first_inst).quantity ≈ 0.8 atol=1e-12
    @test get_position(acc, second_inst).quantity ≈ 0.8 atol=1e-12
    @test getfield.(result.trades, :fill_qty) ≈ [0.8, 0.8] atol=1e-12
    @test cash_balance(acc, cash_asset(acc, :USD)) ≈ 4.0 atol=1e-12
    @test Fastback.check_invariants(acc)

    funded = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.FullyFunded,
        base_currency=CashSpec(:USD),
    )
    deposit!(funded, :USD, 1_000.0)
    old = register_instrument!(funded, spot_instrument(Symbol("OLD/USD"), :OLD, :USD; base_tick=1.0))
    new = register_instrument!(funded, spot_instrument(Symbol("NEW/USD"), :NEW, :USD; base_tick=1.0))
    update_marks!(funded, old, dt, 100.0, 100.0, 100.0)
    update_marks!(funded, new, dt, 100.0, 100.0, 100.0)
    fill_order!(funded, Order(oid!(funded), old, dt, 100.0, 10.0);
        dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    rotated = rebalance!(
        Portfolio(funded),
        dt,
        TargetWeights(old => 0.0, new => 1.0),
    )
    @test [trade.order.inst for trade in rotated.trades] == [old, new]
    @test getfield.(rotated.trades, :fill_qty) == [-10.0, 10.0]
    @test get_position(funded, old).quantity == 0.0
    @test get_position(funded, new).quantity == 10.0
end

@testitem "spread fills and explicit portfolio rolls are deterministic" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 10_000.0)
    expiry_one = DateTime(2028, 3, 31)
    expiry_two = DateTime(2028, 6, 30)
    front = register_instrument!(acc, future_instrument(
        Symbol("ROLLH28"),
        :ROLL,
        :USD;
        expiry=expiry_one,
        base_tick=1.0,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))
    next = register_instrument!(acc, future_instrument(
        Symbol("ROLLM28"),
        :ROLL,
        :USD;
        expiry=expiry_two,
        base_tick=1.0,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))
    dt = DateTime(2028, 1, 2)
    fill_order!(acc, Order(oid!(acc), front, dt, 100.0, 2.0);
        dt=dt, fill_price=100.0, bid=99.5, ask=100.5, last=100.0)
    update_marks!(acc, next, dt, 99.5, 100.5, 100.0)

    model = SpreadFillModel(full_spread_basis_points=200.0)
    result = rebalance!(
        Portfolio(acc),
        dt,
        TargetWeights(next => 0.02);
        rolls=[RollTransition(front, next)],
        fill_model=model,
    )

    @test length(result.trades) == 2
    @test all(trade -> trade.reason == TradeReason.Roll, result.trades)
    @test getfield.(result.trades, :fill_price) == [99.0, 101.0]
    @test get_position(acc, front).quantity == 0.0
    @test get_position(acc, next).quantity == 2.0
    @test Fastback.check_invariants(acc)
end

@testitem "target-weight portfolio rejects options before mutation" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 10_000.0)
    option = register_instrument!(acc, option_instrument(
        Symbol("PORTOPT"),
        :ABC,
        :USD;
        strike=100.0,
        expiry=DateTime(2028, 6, 30),
        right=OptionRight.Call,
    ))
    dt = DateTime(2028, 1, 2)
    @test_throws ArgumentError rebalance!(Portfolio(acc), dt, TargetWeights(option => 0.0))
    @test isempty(acc.trades)
    @test acc.last_event_dt == DateTime(0)
end

@testitem "rebalance workspace survives failures and retains caller-owned results" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    deposit!(acc, :USD, 1_000.0)
    dt = DateTime(2026, 1, 1)
    a = register_instrument!(acc, spot_instrument(:A, :A, :USD))
    b = register_instrument!(acc, spot_instrument(:B, :B, :USD))
    for inst in (a, b)
        update_marks!(acc, inst, dt, 100.0, 100.0, 100.0)
    end
    p = Portfolio(acc)
    first_result = rebalance!(p, dt, TargetWeights(a => 0.5))
    saved = copy(first_result.trades)
    suppressed = rebalance!(p, dt, TargetWeights(a => 0.5, b => 0.01);
        policy=RebalancePolicy(minimum_notional_base=20.0))
    @test suppressed.suppressed == [b.index]
    @test_throws ArgumentError rebalance!(p, dt, TargetWeights(a => 0.1, 1000 => 0.5))
    for i in 1:128
        register_instrument!(acc, spot_instrument(Symbol("LATE", i), :L, :USD))
    end
    rotated = rebalance!(Portfolio(acc), dt, TargetWeights(b => 0.5))
    @test getfield.(rotated.trades, :fill_qty) == [-5.0, 5.0]
    @test first_result.trades == saved
    @test suppressed.suppressed == [b.index]
    @test first_result.trades !== rotated.trades
    @test Fastback.check_invariants(acc)
    exited = rebalance!(p, dt, TargetWeights())
    @test only(exited.trades).fill_qty == -5.0
    @test isempty(acc._event_state.open_positions)
    @test Fastback.check_invariants(acc)
end
