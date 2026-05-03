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
    fill_order!(acc, Order(oid!(acc), usd_inst, dt0 + Day(1), 110.0, -1.0); dt=dt0 + Day(1), fill_price=110.0, bid=110.0, ask=110.0, last=110.0)
    fill_order!(acc, Order(oid!(acc), eur_inst, dt0, 200.0, 1.0); dt=dt0, fill_price=200.0, bid=200.0, ask=200.0, last=200.0)
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
    fill_order!(acc, Order(oid!(acc), usd_inst, dt0 + Day(1), 110.0, -1.0); dt=dt0 + Day(1), fill_price=110.0, bid=110.0, ask=110.0, last=110.0)
    fill_order!(acc, Order(oid!(acc), eur_inst, dt0, 200.0, 1.0); dt=dt0, fill_price=200.0, bid=200.0, ask=200.0, last=200.0)
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

    rets = [0.01, -0.004, 0.007, 0.002]
    summary = performance_summary(acc, rets; periods_per_year=252)

    @test summary isa PerformanceSummary
    @test isapprox(summary.tot_ret, RiskPerf.total_return(rets); atol=1e-12)
    @test summary.tot_ret != round(summary.tot_ret, digits=1)
    @test isapprox(summary.cagr, RiskPerf.cagr(rets, 252); atol=1e-12)
    @test isapprox(summary.max_dd, RiskPerf.max_drawdown_pct(rets; compound=true); atol=1e-12)
    @test isapprox(summary.avg_dd, RiskPerf.average_drawdown_pct(rets; compound=true); atol=1e-12)
    @test isapprox(summary.ulcer, RiskPerf.ulcer_index(rets; compound=true); atol=1e-12)
    @test summary.n_periods == length(rets)
    @test summary.best_ret == maximum(rets)
    @test summary.worst_ret == minimum(rets)
    @test isapprox(summary.positive_period_rate, 0.75; atol=1e-12)
    @test isapprox(summary.expected_shortfall_95, RiskPerf.expected_shortfall(rets, 0.05; method=:historical); atol=1e-12)
    @test isapprox(summary.skewness, RiskPerf.skewness(rets); atol=1e-12)
    @test isapprox(summary.kurtosis, RiskPerf.kurtosis(rets); atol=1e-12)
    @test isapprox(summary.downside_vol, RiskPerf.downside_deviation(rets, 0.0; method=:full) * sqrt(252); atol=1e-12)
    @test summary.max_dd_duration == 1
    @test isapprox(summary.pct_time_in_drawdown, 0.25; atol=1e-12)
    @test isapprox(summary.omega, RiskPerf.omega_ratio(rets, 0.0); atol=1e-12)
    @test summary.n_trades == 3
    @test summary.n_closing_trades == 2
    @test summary.winners == 0.5
    @test summary.losers == 0.5
    @test occursin("tot_ret=$(summary.tot_ret)", repr(summary))
    @test occursin("PerformanceSummary(\n    tot_ret=$(summary.tot_ret),\n    cagr=$(summary.cagr)", repr(summary))

    tbl = performance_summary_table(acc, rets; periods_per_year=252)
    @test Tables.istable(typeof(tbl))
    @test Tables.schema(tbl).names == (
        :tot_ret,
        :cagr,
        :sharpe,
        :sortino,
        :calmar,
        :max_dd,
        :avg_dd,
        :ulcer,
        :vol,
        :n_periods,
        :best_ret,
        :worst_ret,
        :positive_period_rate,
        :expected_shortfall_95,
        :skewness,
        :kurtosis,
        :downside_vol,
        :max_dd_duration,
        :pct_time_in_drawdown,
        :omega,
        :n_trades,
        :n_closing_trades,
        :winners,
        :losers,
    )
    cols = Tables.columntable(tbl)
    @test isapprox(cols.tot_ret[1], summary.tot_ret; atol=1e-12)
    @test isapprox(cols.cagr[1], RiskPerf.cagr(rets, 252); atol=1e-12)
    @test isapprox(cols.vol[1], RiskPerf.volatility(rets; multiplier=252); atol=1e-12)
    @test cols.n_periods == [4]
    @test cols.best_ret == [0.01]
    @test cols.worst_ret == [-0.004]
    @test isapprox(cols.positive_period_rate[1], 0.75; atol=1e-12)
    @test isapprox(cols.expected_shortfall_95[1], summary.expected_shortfall_95; atol=1e-12)
    @test isapprox(cols.skewness[1], summary.skewness; atol=1e-12)
    @test isapprox(cols.kurtosis[1], summary.kurtosis; atol=1e-12)
    @test isapprox(cols.downside_vol[1], summary.downside_vol; atol=1e-12)
    @test cols.max_dd_duration == [1]
    @test isapprox(cols.pct_time_in_drawdown[1], 0.25; atol=1e-12)
    @test isapprox(cols.omega[1], summary.omega; atol=1e-12)
    @test cols.n_trades == [3]
    @test cols.n_closing_trades == [2]
    @test cols.winners == Union{Missing,Float64}[0.5]
    @test cols.losers == Union{Missing,Float64}[0.5]
    @test !(:mar in Tables.schema(tbl).names)
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
    perf = performance_summary(acc, [0.0, 0.0]; periods_per_year=252)

    @test trades.hit_rate == 0.0
    @test perf.n_closing_trades == 1
    @test perf.winners == 0.0
    @test perf.losers == 0.0
end
