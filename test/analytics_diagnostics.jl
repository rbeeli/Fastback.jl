using Dates
using TestItemRunner

@testitem "quote realized PnL helpers and long trade summary" begin
    using Test, Fastback, Dates

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGLONG/USD"), :DIAGLONG, :USD))

    dt0 = DateTime(2026, 1, 1)
    qty = 2.0
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, qty); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    dt1 = dt0 + Day(1)
    close_trade = fill_order!(acc, Order(oid!(acc), inst, dt1, 110.0, -qty); dt=dt1, fill_price=110.0, bid=110.0, ask=110.0, last=110.0)

    @test isapprox(gross_realized_pnl_quote(close_trade), 20.0; atol=1e-12)
    @test isapprox(net_realized_pnl_quote(close_trade), 20.0; atol=1e-12)

    summary = trade_summary(acc)
    @test summary isa TradeSummary
    @test summary.trade_count == 2
    @test summary.realized_trade_count == 1
    @test summary.finite_realized_count == 1
    quote_summary = only(summary.quote_summaries)
    settlement_summary = only(summary.settlement_summaries)
    @test quote_summary isa QuoteTradeSummary
    @test settlement_summary isa SettlementTradeSummary
    @test quote_summary.symbol == :USD
    @test settlement_summary.symbol == :USD
    @test isapprox(quote_summary.gross_realized_pnl_quote, 20.0; atol=1e-12)
    @test isapprox(quote_summary.net_realized_pnl_quote, 20.0; atol=1e-12)
    @test isapprox(quote_summary.net_realized_return, 0.10; atol=1e-12)
    @test isapprox(settlement_summary.gross_realized_pnl, 20.0; atol=1e-12)
end

@testitem "quote realized PnL helpers for profitable short close" begin
    using Test, Fastback, Dates

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGSHORT/USD"), :DIAGSHORT, :USD))

    dt0 = DateTime(2026, 1, 1)
    qty = 2.0
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, -qty); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    dt1 = dt0 + Day(1)
    close_trade = fill_order!(acc, Order(oid!(acc), inst, dt1, 90.0, qty); dt=dt1, fill_price=90.0, bid=90.0, ask=90.0, last=90.0)

    @test realized_return_gross(close_trade) > 0.0
    @test realized_return_net(close_trade) > 0.0
    @test isapprox(gross_realized_pnl_quote(close_trade), 20.0; atol=1e-12)
    @test isapprox(net_realized_pnl_quote(close_trade), 20.0; atol=1e-12)
end

@testitem "quote realized PnL summary uses allocated commissions" begin
    using Test, Fastback, Dates

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=FlatFeeBroker(fixed=1.0))
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGCOMM/USD"), :DIAGCOMM, :USD))

    dt0 = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 2.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    win_dt = dt0 + Day(1)
    win_trade = fill_order!(acc, Order(oid!(acc), inst, win_dt, 110.0, -1.0); dt=win_dt, fill_price=110.0, bid=110.0, ask=110.0, last=110.0)

    loss_dt = dt0 + Day(2)
    loss_trade = fill_order!(acc, Order(oid!(acc), inst, loss_dt, 90.0, -1.0); dt=loss_dt, fill_price=90.0, bid=90.0, ask=90.0, last=90.0)

    expected_realized_commission = 1.0 * (1.0 / 2.0) + 1.0
    expected_win_net_return = 0.10 - expected_realized_commission / 100.0
    expected_loss_net_return = -0.10 - expected_realized_commission / 100.0

    @test isapprox(win_trade.realized_commission_quote, expected_realized_commission; atol=1e-12)
    @test isapprox(loss_trade.realized_commission_quote, expected_realized_commission; atol=1e-12)
    @test isapprox(realized_return_net(win_trade), expected_win_net_return; atol=1e-12)
    @test isapprox(realized_return_net(loss_trade), expected_loss_net_return; atol=1e-12)

    summary = trade_summary(acc.trades)
    quote_summary = only(summary.quote_summaries)
    settlement_summary = only(summary.settlement_summaries)
    @test isapprox(quote_summary.total_commission, 3.0; atol=1e-12)
    @test isapprox(settlement_summary.total_commission, 3.0; atol=1e-12)
    @test isapprox(quote_summary.net_realized_pnl_quote, -3.0; atol=1e-12)
    @test isapprox(quote_summary.net_realized_return, -0.015; atol=1e-12)
    @test isapprox(summary.hit_rate, 0.5; atol=1e-12)
    @test isapprox(quote_summary.hit_rate, 0.5; atol=1e-12)
    @test isapprox(quote_summary.average_win_quote, 8.5; atol=1e-12)
    @test isapprox(quote_summary.average_loss_quote, -11.5; atol=1e-12)
    @test isapprox(quote_summary.payoff_asymmetry, 8.5 / 11.5; atol=1e-12)
end

@testitem "ordinary realized holding period is reconstructed" begin
    using Test, Fastback, Dates

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGHOLD/USD"), :DIAGHOLD, :USD))

    dt0 = DateTime(2026, 1, 1)
    dt1 = dt0 + Day(2)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), inst, dt1, 110.0, -1.0); dt=dt1, fill_price=110.0, bid=110.0, ask=110.0, last=110.0)

    periods = realized_holding_periods(acc)
    @test length(periods) == 1
    @test periods[1] isa RealizedHoldingPeriod
    @test periods[1].symbol == inst.spec.symbol
    @test periods[1].entry_date == dt0
    @test periods[1].exit_date == dt1
    @test isapprox(periods[1].quantity, 1.0; atol=1e-12)
    @test periods[1].holding_period == convert(Millisecond, Day(2))

    summary = holding_period_summary(acc.trades)
    @test summary isa HoldingPeriodSummary
    @test summary.realized_lot_count == 1
    @test isapprox(summary.realized_quantity, 1.0; atol=1e-12)
    @test summary.average_holding_period == convert(Millisecond, Day(2))
    @test summary.median_holding_period == convert(Millisecond, Day(2))
end

@testitem "partial exit holding periods use FIFO exposure weights" begin
    using Test, Fastback, Dates

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGPART/USD"), :DIAGPART, :USD))

    dt0 = DateTime(2026, 1, 1)
    dt1 = dt0 + Day(1)
    dt3 = dt0 + Day(3)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 3.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), inst, dt1, 101.0, -1.0); dt=dt1, fill_price=101.0, bid=101.0, ask=101.0, last=101.0)
    fill_order!(acc, Order(oid!(acc), inst, dt3, 103.0, -2.0); dt=dt3, fill_price=103.0, bid=103.0, ask=103.0, last=103.0)

    periods = realized_holding_periods(acc.trades)
    @test length(periods) == 2
    @test isapprox(periods[1].quantity, 1.0; atol=1e-12)
    @test periods[1].holding_period == convert(Millisecond, Day(1))
    @test isapprox(periods[2].quantity, 2.0; atol=1e-12)
    @test periods[2].holding_period == convert(Millisecond, Day(3))

    summary = holding_period_summary(acc)
    @test summary.realized_lot_count == 2
    @test isapprox(summary.realized_quantity, 3.0; atol=1e-12)
    @test summary.average_holding_period == Millisecond(201_600_000)
    @test summary.median_holding_period == convert(Millisecond, Day(3))
end

@testitem "sub-millisecond holding periods preserve timestamp resolution" begin
    using Test, Fastback, Dates

    acc = Account(;
        time_type=Time,
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
    )
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGNANO/USD"), :DIAGNANO, :USD; time_type=Time))

    dt0 = Time(0)
    dt1 = dt0 + Nanosecond(1)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), inst, dt1, 100.0, -1.0); dt=dt1, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    periods = realized_holding_periods(acc)
    @test length(periods) == 1
    @test periods[1].holding_period == Nanosecond(1)
    @test periods[1].holding_period isa Nanosecond

    summary = holding_period_summary(acc)
    @test summary.average_holding_period == Nanosecond(1)
    @test summary.median_holding_period == Nanosecond(1)
end

@testitem "P&L concentration groups realized trades by quote symbol and sorts by absolute net P&L" begin
    using Test, Fastback, Dates, Tables

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=FlatFeeBroker(fixed=1.0))
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGCONC/USD"), :DIAGCONC, :USD))

    dt0 = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 2.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    win_trade = fill_order!(acc, Order(oid!(acc), inst, dt0 + Day(1), 110.0, -1.0); dt=dt0 + Day(1), fill_price=110.0, bid=110.0, ask=110.0, last=110.0)
    loss_trade = fill_order!(acc, Order(oid!(acc), inst, dt0 + Day(2), 90.0, -1.0); dt=dt0 + Day(2), fill_price=90.0, bid=90.0, ask=90.0, last=90.0)

    tbl = pnl_concentration(acc; by=:trade)
    @test Tables.istable(typeof(tbl))
    @test Tables.columnaccess(typeof(tbl))
    @test Tables.schema(tbl).names == (
        :bucket,
        :quote_symbol,
        :realized_trade_count,
        :gross_realized_pnl_quote,
        :net_realized_pnl_quote,
        :share_of_abs_pnl,
        :share_of_net_pnl,
    )
    @test size(tbl, 1) == 2
    @test tbl.bucket == [loss_trade.tid, win_trade.tid]
    @test tbl.quote_symbol == [:USD, :USD]
    @test tbl.realized_trade_count == [1, 1]
    @test isapprox(tbl.net_realized_pnl_quote[1], -11.5; atol=1e-12)
    @test isapprox(tbl.net_realized_pnl_quote[2], 8.5; atol=1e-12)
    @test isapprox(tbl.share_of_abs_pnl[1], 11.5 / 20.0; atol=1e-12)
end

@testitem "P&L concentration shares are normalized per quote currency" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
        exchange_rates=er,
    )
    deposit!(acc, :USD, 10_000.0)
    register_cash_asset!(acc, CashSpec(:EUR))
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.2)

    usd_inst = register_instrument!(acc, spot_instrument(
        Symbol("DIAGUSD/USD"),
        :DIAGUSD,
        :USD;
        margin_init_long=0.0,
        margin_maint_long=0.0,
    ))
    eur_inst = register_instrument!(acc, spot_instrument(
        Symbol("DIAGEUR/EURUSD"),
        :DIAGEUR,
        :EUR;
        settle_symbol=:USD,
        margin_symbol=:USD,
        margin_init_long=0.0,
        margin_maint_long=0.0,
    ))

    dt0 = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), usd_inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), eur_inst, dt0, 200.0, 1.0); dt=dt0, fill_price=200.0, bid=200.0, ask=200.0, last=200.0)
    fill_order!(acc, Order(oid!(acc), usd_inst, dt0 + Day(1), 110.0, -1.0); dt=dt0 + Day(1), fill_price=110.0, bid=110.0, ask=110.0, last=110.0)
    fill_order!(acc, Order(oid!(acc), eur_inst, dt0 + Day(1), 220.0, -1.0); dt=dt0 + Day(1), fill_price=220.0, bid=220.0, ask=220.0, last=220.0)

    tbl = pnl_concentration(acc; by=:trade)
    @test length(tbl.bucket) == 2
    @test Set(tbl.quote_symbol) == Set([:USD, :EUR])
    @test all(isapprox.(tbl.share_of_abs_pnl, 1.0; atol=1e-12))
    @test all(isapprox.(tbl.share_of_net_pnl, 1.0; atol=1e-12))
end

@testitem "trade summary groups monetary diagnostics by currency" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    acc = Account(;
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
        exchange_rates=er,
    )
    deposit!(acc, :USD, 10_000.0)
    register_cash_asset!(acc, CashSpec(:EUR))
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.2)

    usd_inst = register_instrument!(acc, spot_instrument(
        Symbol("DIAGSUMUSD/USD"),
        :DIAGSUMUSD,
        :USD;
        margin_init_long=0.0,
        margin_maint_long=0.0,
    ))
    eur_inst = register_instrument!(acc, spot_instrument(
        Symbol("DIAGSUMEUR/EUR"),
        :DIAGSUMEUR,
        :EUR;
        margin_init_long=0.0,
        margin_maint_long=0.0,
    ))

    dt0 = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), usd_inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), eur_inst, dt0, 200.0, 1.0); dt=dt0, fill_price=200.0, bid=200.0, ask=200.0, last=200.0)
    fill_order!(acc, Order(oid!(acc), usd_inst, dt0 + Day(1), 110.0, -1.0); dt=dt0 + Day(1), fill_price=110.0, bid=110.0, ask=110.0, last=110.0)
    fill_order!(acc, Order(oid!(acc), eur_inst, dt0 + Day(1), 220.0, -1.0); dt=dt0 + Day(1), fill_price=220.0, bid=220.0, ask=220.0, last=220.0)

    summary = trade_summary(acc)
    quote_by_symbol = Dict(s.symbol => s for s in summary.quote_summaries)
    settle_by_symbol = Dict(s.symbol => s for s in summary.settlement_summaries)

    @test length(summary.quote_summaries) == 2
    @test length(summary.settlement_summaries) == 2
    @test isapprox(quote_by_symbol[:USD].net_realized_pnl_quote, 10.0; atol=1e-12)
    @test isapprox(quote_by_symbol[:EUR].net_realized_pnl_quote, 20.0; atol=1e-12)
    @test isapprox(settle_by_symbol[:USD].gross_realized_pnl, 10.0; atol=1e-12)
    @test isapprox(settle_by_symbol[:EUR].gross_realized_pnl, 20.0; atol=1e-12)
    @test isapprox(quote_by_symbol[:USD].net_realized_return, 0.10; atol=1e-12)
    @test isapprox(quote_by_symbol[:EUR].net_realized_return, 0.10; atol=1e-12)
end

@testitem "P&L concentration preserves schema without realized trades" begin
    using Test, Fastback, Dates, Tables

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
    deposit!(acc, :USD, 10_000.0)

    tbl = pnl_concentration(acc)
    @test Tables.istable(typeof(tbl))
    @test Tables.columnaccess(typeof(tbl))
    @test Tables.schema(tbl).names == (
        :bucket,
        :quote_symbol,
        :realized_trade_count,
        :gross_realized_pnl_quote,
        :net_realized_pnl_quote,
        :share_of_abs_pnl,
        :share_of_net_pnl,
    )
    @test size(tbl) == (0, 7)

    cols = Tables.columntable(tbl)
    @test propertynames(cols) == Tables.schema(tbl).names
    @test isempty(cols.bucket)
    @test eltype(cols.bucket) == Union{Int,Symbol,Date}
    @test cols.quote_symbol == Symbol[]
    @test cols.realized_trade_count == Int[]
    @test cols.gross_realized_pnl_quote == Float64[]
    @test cols.net_realized_pnl_quote == Float64[]
    @test cols.share_of_abs_pnl == Float64[]
    @test cols.share_of_net_pnl == Float64[]
end

@testitem "P&L concentration rejects period grouping for time-only trades" begin
    using Test, Fastback, Dates

    acc = Account(;
        time_type=Time,
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
    )
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGTIME/USD"), :DIAGTIME, :USD; time_type=Time))

    dt0 = Time(0)
    dt1 = dt0 + Nanosecond(1)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), inst, dt1, 101.0, -1.0); dt=dt1, fill_price=101.0, bid=101.0, ask=101.0, last=101.0)

    @test size(pnl_concentration(acc; by=:trade), 1) == 1

    err = try
        pnl_concentration(acc; by=:period)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("date-bearing timestamps", sprint(showerror, err))
end

@testitem "performance summary includes return and trade diagnostics" begin
    using Test, Fastback, Dates, RiskPerf, Tables

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGPERF/USD"), :DIAGPERF, :USD))

    dt0 = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 2.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), inst, dt0 + Day(1), 110.0, -1.0); dt=dt0 + Day(1), fill_price=110.0, bid=110.0, ask=110.0, last=110.0)
    fill_order!(acc, Order(oid!(acc), inst, dt0 + Day(2), 90.0, -1.0); dt=dt0 + Day(2), fill_price=90.0, bid=90.0, ask=90.0, last=90.0)

    rets = [0.01, -0.004, NaN, 0.007, 0.002]
    finite = filter(isfinite, rets)
    account_summary = account_performance_summary(acc, rets, PerformanceConfig(252))
    summary = account_summary.performance

    @test account_summary isa AccountPerformanceSummary
    @test summary == performance_summary(rets)
    @test summary.observations == 4
    @test summary.ignored_observations == 1
    @test summary.total_return == RiskPerf.total_return(finite)
    @test summary.annualized_return == RiskPerf.cagr(finite, 252)
    @test summary.annualized_volatility == RiskPerf.volatility(finite; multiplier=252)
    @test summary.maximum_drawdown == RiskPerf.max_drawdown_pct(finite)
    @test summary.average_drawdown == RiskPerf.average_drawdown_pct(finite)
    @test summary.ulcer_index == RiskPerf.ulcer_index(finite)
    @test summary.calmar_ratio == RiskPerf.calmar_ratio(finite, 252)
    @test summary.best_return == 0.01
    @test summary.worst_return == -0.004
    @test summary.positive_period_rate == 0.75
    @test summary.expected_shortfall == RiskPerf.expected_shortfall(finite, 0.05; method=:historical)
    @test summary.skewness == RiskPerf.skewness(finite)
    @test summary.excess_kurtosis == RiskPerf.kurtosis(finite)
    @test summary.annualized_downside_volatility == RiskPerf.downside_deviation(finite, 0.0; method=:full) * sqrt(252)
    @test summary.maximum_drawdown_duration == 1
    @test summary.time_in_drawdown_rate == 0.25
    @test summary.omega_ratio == RiskPerf.omega_ratio(finite, 0.0)
    @test account_summary.applied_trade_count == 3
    @test account_summary.closing_trade_count == 2
    @test account_summary.winner_rate == 0.5
    @test account_summary.loser_rate == 0.5
    @test occursin("PerformanceSummary(\n    observations=4,\n    ignored_observations=1,", repr(summary))
    @test occursin("applied_trade_count=3", repr(account_summary))

    tbl = performance_summary_table(account_summary)
    @test Tables.istable(typeof(tbl))
    @test Tables.schema(tbl).names == (fieldnames(PerformanceSummary)...,
        :applied_trade_count, :closing_trade_count, :winner_rate, :loser_rate)
    cols = Tables.columntable(tbl)
    @test cols.total_return == [summary.total_return]
    @test cols.maximum_drawdown_duration == [1]
    @test cols.applied_trade_count == [3]
    @test cols.winner_rate == Union{Missing,Float64}[0.5]
    @test Tables.schema(performance_summary_table(summary)).names == fieldnames(PerformanceSummary)
end

@testitem "performance summary reports undefined metrics as nothing" begin
    using Test, Fastback, Tables

    empty = performance_summary([NaN, Inf])
    @test empty.observations == 0
    @test empty.ignored_observations == 2
    @test isnothing(empty.total_return)
    @test empty.maximum_drawdown_duration == 0
    @test isnothing(empty.time_in_drawdown_rate)

    rising = performance_summary([0.01, 0.02])
    @test rising.maximum_drawdown == 0.0
    @test isnothing(rising.calmar_ratio)
    @test isnothing(rising.omega_ratio)
    @test all(ismissing, Tables.columntable(performance_summary_table(rising)).calmar_ratio)

    single = performance_summary([0.01])
    @test isnothing(single.annualized_volatility)
    @test isnothing(single.sharpe_ratio)
end

@testitem "performance summary converts annual risk thresholds to periodic rates" begin
    using Test, Fastback, RiskPerf

    returns = [0.01, 0.02, 0.03, 0.04]
    periods_per_year = 4.0
    annual_rate = 0.10
    periodic_rate = annual_rate / periods_per_year
    summary = performance_summary(returns, PerformanceConfig(periods_per_year;
        annual_risk_free_rate=annual_rate, annual_minimum_acceptable_return=annual_rate))

    @test summary.sharpe_ratio == RiskPerf.sharpe_ratio(returns; multiplier=periods_per_year, risk_free=periodic_rate)
    @test summary.sortino_ratio == RiskPerf.sortino_ratio(returns; multiplier=periods_per_year, MAR=periodic_rate)
    @test summary.annualized_downside_volatility ==
          RiskPerf.downside_deviation(returns, periodic_rate; method=:full) * sqrt(periods_per_year)
    @test summary.omega_ratio == RiskPerf.omega_ratio(returns, periodic_rate)
    @test isapprox(something(summary.sharpe_ratio), 0.0; atol=1e-12)

    @test_throws ArgumentError PerformanceConfig(0.0)
    @test_throws ArgumentError PerformanceConfig(Inf)
    @test_throws ArgumentError PerformanceConfig(252; annual_risk_free_rate=Inf)
    @test_throws ArgumentError PerformanceConfig(252; annual_minimum_acceptable_return=NaN)
    @test_throws ArgumentError PerformanceConfig(252; expected_shortfall_probability=0.0)
    @test_throws ArgumentError PerformanceConfig(252; expected_shortfall_probability=1.5)
    @test_throws ArgumentError PerformanceConfig(252; drawdown_method=:geometric)
end

@testitem "performance summary honors expected-shortfall probability and drawdown method" begin
    using Test, Fastback, RiskPerf

    returns = [0.05, -0.10, 0.02, -0.03, 0.04]
    whole = performance_summary(returns, PerformanceConfig(252; expected_shortfall_probability=1.0))
    @test whole.expected_shortfall == RiskPerf.mean_excess(returns, 0.0)

    additive = performance_summary(returns, PerformanceConfig(252; drawdown_method=:additive))
    @test additive.maximum_drawdown == RiskPerf.max_drawdown_pct(returns; compound=false)
    @test additive.ulcer_index == RiskPerf.ulcer_index(returns; compound=false)
end

@testitem "flat closing trades are not counted as performance winners" begin
    using Test, Fastback, Dates

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGFLAT/USD"), :DIAGFLAT, :USD))

    dt0 = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), inst, dt0 + Day(1), 100.0, -1.0); dt=dt0 + Day(1), fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    trades = trade_summary(acc)
    perf = account_performance_summary(acc, [0.0, 0.0])

    @test trades.hit_rate == 0.0
    @test perf.closing_trade_count == 1
    @test perf.winner_rate == 0.0
    @test perf.loser_rate == 0.0
end

@testitem "holding periods close lots that match within rounding noise" begin
    using Test, Fastback, Dates

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGDUST/USD"), :DIAGDUST, :USD; base_tick=0.1))

    dt0 = DateTime(2026, 1, 1)
    for (day, qty) in ((0, 0.1), (1, 0.2), (2, -0.3), (3, 1.0), (4, -1.0))
        dt = dt0 + Day(day)
        fill_order!(acc, Order(oid!(acc), inst, dt, 100.0, qty); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    end

    periods = realized_holding_periods(acc)
    @test [period.entry_date for period in periods] == [dt0, dt0 + Day(1), dt0 + Day(3)]
    @test all(period -> period.quantity > 0.05, periods)
end

@testitem "holding periods give inconsistent exposure an unknown entry" begin
    using Test, Fastback, Dates

    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("DIAGGAP/USD"), :DIAGGAP, :USD))

    dt0 = DateTime(2026, 1, 1)
    for (day, qty) in ((0, 2.0), (1, -1.0), (2, -1.0))
        dt = dt0 + Day(day)
        fill_order!(acc, Order(oid!(acc), inst, dt, 100.0, qty); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    end

    @test isempty(realized_holding_periods(acc.trades[[1, 3]]))
end
