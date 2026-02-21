using Dates
using TestItemRunner

@testitem "periodic_collector" begin
    using Test, Fastback, Dates
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]
    # periodic_collector
    f, collected = periodic_collector(Float64, Second(1))
    for i in eachindex(dts)
        should_collect(collected, dts[i]) && f(dts[i], data[i])
    end
    @test length(values(collected)) == 5
    @test all(dates(collected) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
    @test collected.last_dt == dts[end]
end

@testitem "predicate_collector" begin
    using Test, Fastback, Dates
    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]
    # predicate_collector
    predicate = (collected, dt) -> (dt - collected.last_dt) >= Second(1)
    f, collected = predicate_collector(Float64, predicate, 0.0)
    for i in eachindex(dts)
        should_collect(collected, dts[i]) && f(dts[i], data[i])
    end
    @test length(dates(collected)) == 5
    @test all(dates(collected) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
    @test collected.last_dt == dts[end]
end

@testitem "min_value_collector" begin
    using Test, Fastback, Dates

    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]

    # min_value_collector
    f, collected = min_value_collector(Float64)
    for i in eachindex(dts)
        should_collect(collected, data[i]) && f(dts[i], data[i])
    end

    @test collected.min_value == minimum(data)
    @test collected.dt == dts[indexin(minimum(data), data)][1]
end

@testitem "max_value_collector" begin
    using Test, Fastback, Dates

    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]

    # max_value_collector
    f, collected = max_value_collector(Float64)
    for i in eachindex(dts)
        should_collect(collected, data[i]) && f(dts[i], data[i])
    end

    @test collected.max_value == maximum(data)
    @test collected.dt == dts[indexin(maximum(data), data)][1]
end

@testitem "drawdown_collector_pnl" begin
    using Test, Fastback, Dates

    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]

    # drawdown_collector (P&L)
    f, collected = drawdown_collector(DrawdownMode.PnL, Second(1))
    for i in eachindex(dts)
        should_collect(collected, dts[i]) && f(dts[i], data[i])
    end
    
    @test length(dates(collected)) == 5
    @test length(values(collected)) == 5
    @test all(dates(collected) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
    @test collected.last_dt == dts[end]
    @test all(values(collected) .== [0.0, -11, -5, -5, -10])
end

@testitem "drawdown_collector_pct" begin
    using Test, Fastback, Dates, Tables

    # every 500 ms from 1 sec to 5 sec
    dts = map(x -> DateTime(2000, 1, 1) + Millisecond(x), 1000:500:5000)
    data = [100.0, 110.0, 99.0, 102.0, 105.0, 105.0, 105.0, 120.0, 110.0]

    # drawdown_collector (%)
    f, collected = drawdown_collector(DrawdownMode.Percentage, Second(1))
    for i in eachindex(dts)
        should_collect(collected, dts[i]) && f(dts[i], data[i])
    end

    @test length(dates(collected)) == 5
    @test length(values(collected)) == 5
    @test all(dates(collected) .== map(x -> DateTime(2000, 1, 1) + Second(x), 1:5))
    @test collected.last_dt == dts[end]
    @test Tables.schema(collected).names == (:date, :drawdown)
    @test all(values(collected) .≈ [0.0, -11 / 110, -5 / 110, -5 / 110, -10 / 120])
end

@testitem "periodic_collector with Date" begin
    using Test, Fastback, Dates, Tables

    start_date = Date(2020, 1, 1)
    collect_equity, equity_data = periodic_collector(Float64, Day(1); time_type=Date)

    for offset in 0:2
        dt = start_date + Day(offset)
        should_collect(equity_data, dt) && collect_equity(dt, 100.0 + offset)
    end

    @test equity_data.last_dt == start_date + Day(2)
    schema = Tables.schema(equity_data)
    @test schema.types[1] == Date
    rows = collect(Tables.rows(equity_data))
    @test rows[1].date isa Date
    @test rows[end].date == start_date + Day(2)
end

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
    register_instrument!(acc, inst_a)
    register_instrument!(acc, inst_b)

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
    register_instrument!(acc, inst)

    collect_weights, collected = portfolio_weights_collector(acc, [inst], Day(1))
    dt = DateTime(2020, 1, 1, 10, 0, 0)
    should_collect(collected, dt) && collect_weights(dt)

    @test dates(collected) == [dt]
    @test collected.symbols == [:AAA]
    @test values(collected)[1] == [0.0]
end
