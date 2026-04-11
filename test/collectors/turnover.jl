using Dates
using TestItemRunner

@testitem "turnover_collector tracks gross traded notional by period" begin
    using Test, Fastback, Dates, Tables

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
    )
    deposit!(acc, :USD, 1_000.0)
    inst = register_instrument!(acc, spot_instrument(:AAA, :AAA, :USD))

    collect_turnover, collected = turnover_collector(acc, Day(1))

    dt1 = DateTime(2020, 1, 1, 10, 0, 0)
    order1 = Order(oid!(acc), inst, dt1, 100.0, 1.0)
    fill_order!(acc, order1; dt=dt1, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    should_collect(collected, dt1) && collect_turnover(dt1)

    equity1 = equity_base_ccy(acc)
    @test dates(collected) == [dt1]
    @test collected.gross_traded_notionals ≈ [100.0]
    @test collected.equities ≈ [equity1]
    @test values(collected) ≈ [100.0 / (2.0 * equity1)]
    @test @inferred(Fastback._turnover_value(100.0, equity1, TurnoverMode.RoundTrip)) ≈ values(collected)[1]

    dt_mid = dt1 + Hour(1)
    order2 = Order(oid!(acc), inst, dt_mid, 110.0, -0.5)
    fill_order!(acc, order2; dt=dt_mid, fill_price=110.0, bid=110.0, ask=110.0, last=110.0)
    should_collect(collected, dt_mid) && collect_turnover(dt_mid)

    @test length(dates(collected)) == 1
    @test collected.pending_gross_traded_notional ≈ 55.0
    @test collected.last_trade_index == length(acc.trades)

    dt2 = dt1 + Day(1)
    should_collect(collected, dt2) && collect_turnover(dt2)
    equity2 = equity_base_ccy(acc)

    @test dates(collected) == [dt1, dt2]
    @test collected.gross_traded_notionals ≈ [100.0, 55.0]
    @test collected.equities ≈ [equity1, equity2]
    @test values(collected) ≈ [100.0 / (2.0 * equity1), 55.0 / (2.0 * equity2)]
    @test collected.pending_gross_traded_notional == 0.0
    @test collected.last_dt == dt2

    @test Tables.schema(collected).names == (:date, :gross_traded_notional, :equity, :turnover, :mode)
    rows = collect(Tables.rows(collected))
    @test rows[1].gross_traded_notional ≈ 100.0
    @test rows[2].turnover ≈ values(collected)[2]
    @test rows[2].mode == TurnoverMode.RoundTrip
end

@testitem "turnover_collector supports one-way notional turnover" begin
    using Test, Fastback, Dates

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
    )
    deposit!(acc, :USD, 1_000.0)
    inst = register_instrument!(acc, spot_instrument(:AAA_ONEWAY, :AAA, :USD))

    collect_turnover, collected = turnover_collector(acc, Day(1); mode=TurnoverMode.OneWay)

    dt = DateTime(2020, 1, 1, 10, 0, 0)
    order = Order(oid!(acc), inst, dt, 100.0, 1.0)
    fill_order!(acc, order; dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    should_collect(collected, dt) && collect_turnover(dt)

    equity_value = equity_base_ccy(acc)
    @test collected.mode == TurnoverMode.OneWay
    @test collected.gross_traded_notionals ≈ [100.0]
    @test values(collected) ≈ [100.0 / equity_value]
end

@testitem "turnover_collector converts quote notional into base currency" begin
    using Test, Fastback, Dates

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:CHF),
        broker=NoOpBroker(),
    )
    register_cash_asset!(acc, CashSpec(:USD))
    update_rate!(acc, :USD, :CHF, 0.5)
    deposit!(acc, :CHF, 1_000.0)
    deposit!(acc, :USD, 1_000.0)
    inst = register_instrument!(acc, spot_instrument(:AAAUSD_TURNOVER, :AAA, :USD))

    collect_turnover, collected = turnover_collector(acc, Day(1))

    dt = DateTime(2020, 1, 1, 10, 0, 0)
    order = Order(oid!(acc), inst, dt, 100.0, 1.0)
    fill_order!(acc, order; dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    should_collect(collected, dt) && collect_turnover(dt)

    equity_value = equity_base_ccy(acc)
    @test collected.gross_traded_notionals ≈ [50.0]
    @test collected.equities ≈ [equity_value]
    @test values(collected) ≈ [50.0 / (2.0 * equity_value)]
end

@testitem "turnover_collector uses fill-time FX for gross traded notional" begin
    using Test, Fastback, Dates

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:CHF),
        broker=NoOpBroker(),
    )
    register_cash_asset!(acc, CashSpec(:USD))
    update_rate!(acc, :USD, :CHF, 0.5)
    deposit!(acc, :CHF, 1_000.0)
    deposit!(acc, :USD, 1_000.0)
    inst = register_instrument!(acc, spot_instrument(:AAAUSD_TURNOVER_FX, :AAA, :USD))

    collect_turnover, collected = turnover_collector(acc, Day(1))

    dt = DateTime(2020, 1, 1, 10, 0, 0)
    order = Order(oid!(acc), inst, dt, 100.0, 1.0)
    trade = fill_order!(acc, order; dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    @test trade.notional_base ≈ 50.0

    update_rate!(acc, :USD, :CHF, 0.8)
    should_collect(collected, dt) && collect_turnover(dt)

    @test collected.gross_traded_notionals ≈ [50.0]
    @test collected.gross_traded_notionals[1] != 80.0
end

@testitem "turnover_collector returns NaN for nonpositive equity" begin
    using Test, Fastback

    @test isnan(Fastback._turnover_value(100.0, 0.0, TurnoverMode.RoundTrip))
    @test isnan(Fastback._turnover_value(100.0, -1.0, TurnoverMode.OneWay))
end

@testitem "turnover_collector requires tracked trades" begin
    using Test, Fastback, Dates

    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
        track_trades=false,
    )

    @test_throws ArgumentError turnover_collector(acc, Day(1))
end
