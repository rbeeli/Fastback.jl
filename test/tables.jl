using Dates
using TestItemRunner

@testsnippet TablesTestSetup begin
    using Test, Fastback, Dates, Tables, DataFrames

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD; digits=2), 1_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("ABC/USD"),
        :ABC,
        :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.0,
        margin_init_short=0.0,
        margin_maint_long=0.0,
        margin_maint_short=0.0,
    ))

    dt₁ = DateTime(2020, 1, 1, 9)
    order₁ = Order(oid!(acc), inst, dt₁, 10.0, 1.0)
    fill_order!(acc, order₁; dt=dt₁, fill_price=10.0, commission=0.5)

    dt₂ = DateTime(2020, 1, 2, 9)
    order₂ = Order(oid!(acc), inst, dt₂, 12.0, -2.0)
    fill_order!(acc, order₂; dt=dt₂, fill_price=12.0, commission=0.25)
end

@testitem "trades_table" setup=[TablesTestSetup] begin
    tbl = trades_table(acc)
    trade_schema = Tables.schema(tbl)
    @test trade_schema.names == (
        :tid,
        :oid,
        :trade_date,
        :order_date,
        :symbol,
        :side,
        :fill_price,
        :fill_qty,
        :remaining_qty,
        :take_profit,
        :stop_loss,
        :realized_pnl_settle,
        :realized_qty,
        :position_qty,
        :position_price,
        :commission_settle,
        :cash_delta_settle,
        :reason,
    )
    trade_rows = collect(Tables.rows(tbl))
    @test length(trade_rows) == length(acc.trades)
    @test trade_rows[1].oid == order₁.oid
    @test trade_rows[end].realized_pnl_settle ≈ 1.75 atol = 1e-8
    @test trade_rows[1].cash_delta_settle ≈ -0.5
    @test trade_rows[end].cash_delta_settle ≈ 1.75
    trade_cols = Tables.columntable(tbl)
    @test trade_cols.symbol == fill(inst.symbol, length(acc.trades))

    println(DataFrame(tbl))
end

@testitem "trades_table uses settlement currency for quote/settle mismatch" begin
    using Test, Fastback, Dates, Tables

    er = SpotExchangeRates()
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD, exchange_rates=er)
    usd = Cash(:USD; digits=4)
    eur = Cash(:EUR; digits=2)
    deposit!(acc, usd, 5_000.0)
    register_cash_asset!(acc, eur)
    update_rate!(er, eur, usd, 1.2)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("FX/EURUSD"),
            :FX,
            :EUR;
            settle_symbol=:USD,
            settlement=SettlementStyle.Asset,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.0,
            margin_init_short=0.0,
            margin_maint_long=0.0,
            margin_maint_short=0.0,
        ),
    )

    dt = DateTime(2025, 1, 1)
    fill_price = 10.0
    qty = 1.0
    commission_quote = 2.0
    order = Order(oid!(acc), inst, dt, fill_price, qty)
    trade = fill_order!(acc, order; dt=dt, fill_price=fill_price, commission=commission_quote)

    tbl = trades_table(acc)
    row = only(Tables.rows(tbl))

    commission_settle = commission_quote * 1.2
    expected_cash_delta = to_settle(acc, inst, -(fill_price * qty * inst.multiplier) - commission_quote)

    @test trade === acc.trades[end]
    @test row.commission_settle ≈ commission_settle atol=1e-12
    @test row.realized_pnl_settle ≈ -commission_settle atol=1e-12
    @test row.cash_delta_settle ≈ expected_cash_delta atol=1e-12
    @test row.symbol == inst.symbol
end

@testitem "positions_table" setup=[TablesTestSetup] begin
    tbl = positions_table(acc)
    schema = Tables.schema(tbl)
    @test schema.names == (
        :index,
        :symbol,
        :qty,
        :avg_entry_price,
        :avg_settle_price,
        :pnl_quote,
        :base_ccy,
        :quote_ccy,
        :last_oid,
        :last_tid,
    )

    rows = collect(Tables.rows(tbl))
    @test length(rows) == length(acc.positions)
    pos_row = only(rows)
    @test pos_row.symbol == inst.symbol
    @test pos_row.qty ≈ -1.0
    @test pos_row.avg_entry_price ≈ 12.0
    @test pos_row.avg_settle_price ≈ 12.0
    @test pos_row.base_ccy == inst.base_symbol
    @test pos_row.quote_ccy == inst.quote_symbol
    @test pos_row.last_oid == order₂.oid
    @test pos_row.last_tid == acc.trades[end].tid
end

@testitem "balances_table" setup=[TablesTestSetup] begin
    tbl = balances_table(acc)
    balance_schema = Tables.schema(tbl)
    @test balance_schema.names == (:index, :symbol, :balance, :digits)
    balance_row = only(Tables.rows(tbl))
    @test balance_row.symbol == :USD
    @test balance_row.balance ≈ cash_balance(acc, :USD)

    println(DataFrame(tbl))
end

@testitem "equities_table" setup=[TablesTestSetup] begin
    tbl = equities_table(acc)
    equity_schema = Tables.schema(tbl)
    @test equity_schema.names == (:index, :symbol, :equity, :digits)
    equity_row = only(Tables.rows(tbl))
    @test equity_row.symbol == :USD
    @test equity_row.equity ≈ equity(acc, :USD)

    println(DataFrame(tbl))
end

@testitem "periodic_collector" begin
    using Test, Fastback, Dates, Tables, DataFrames

    start_dt = DateTime(2020, 1, 1)

    collect_equity, equity_data = periodic_collector(Float64, Hour(1))
    for (i, v) in enumerate(1000.0 .+ 10.0 .* collect(0:2))
        dt = start_dt + Hour(i - 1)
        collect_equity(dt, v)
    end

    equity_schema = Tables.schema(equity_data)
    @test equity_schema.names == (:date, :value)
    equity_rows = collect(Tables.rows(equity_data))
    @test length(equity_rows) == 3
    @test equity_rows[1].date == start_dt
    @test equity_rows[end].value == 1020.0

    println(DataFrame(equity_data))
end

@testitem "drawdown_collector" begin
    using Test, Fastback, Dates, Tables, DataFrames

    start_dt = DateTime(2020, 1, 1)

    collect_drawdown, drawdown_data = drawdown_collector(DrawdownMode.Percentage, Hour(1))
    equity_series = [1_000.0, 1_050.0, 1_000.0, 950.0]
    for (i, val) in enumerate(equity_series)
        dt = start_dt + Hour(i - 1)
        collect_drawdown(dt, val)
    end

    drawdown_schema = Tables.schema(drawdown_data)
    @test drawdown_schema.names == (:date, :drawdown)
    drawdown_rows = collect(Tables.rows(drawdown_data))
    @test !isempty(drawdown_rows)
    @test drawdown_rows[1].date == start_dt
    @test drawdown_rows[end].drawdown ≈ -0.0952381 atol=1e-6

    println(DataFrame(drawdown_data))
end
