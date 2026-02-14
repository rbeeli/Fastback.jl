using Dates
using TestItemRunner

@testsnippet TablesTestSetup begin
    using Test, Fastback, Dates, Tables, DataFrames

    base_currency=CashSpec(:USD)
    acc = Account(; mode=AccountMode.Margin, base_currency=base_currency, broker=FlatFeeBroker(fixed=0.5))
    deposit!(acc, :USD, 1_000.0)

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
    fill_order!(acc, order₁; dt=dt₁, fill_price=10.0, bid=10.0, ask=10.0, last=10.0)

    dt₂ = DateTime(2020, 1, 2, 9)
    order₂ = Order(oid!(acc), inst, dt₂, 12.0, -2.0)
    fill_order!(acc, order₂; dt=dt₂, fill_price=12.0, bid=12.0, ask=12.0, last=12.0)
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
        :settlement_style,
        :side,
        :fill_price,
        :fill_qty,
        :remaining_qty,
        :take_profit,
        :stop_loss,
        :fill_pnl_settle,
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
    @test trade_rows[end].fill_pnl_settle ≈ 2.0 atol = 1e-8
    @test trade_rows[1].cash_delta_settle ≈ -10.5
    @test trade_rows[end].cash_delta_settle ≈ 23.5
    @test trade_rows[end].settlement_style == SettlementStyle.Asset
    trade_cols = Tables.columntable(tbl)
    @test trade_cols.symbol == fill(inst.symbol, length(acc.trades))

    println(DataFrame(tbl))
end

@testitem "trades_table uses settlement currency for quote/settle mismatch" begin
    using Test, Fastback, Dates, Tables

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(; mode=AccountMode.Margin, base_currency=base_currency, exchange_rates=er, broker=FlatFeeBroker(fixed=2.0))
    deposit!(acc, :USD, 5_000.0)
    register_cash_asset!(acc, CashSpec(:EUR))
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.2)

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
    trade = fill_order!(acc, order; dt=dt, fill_price=fill_price, bid=fill_price, ask=fill_price, last=fill_price)

    tbl = trades_table(acc)
    row = only(Tables.rows(tbl))

    commission_settle = commission_quote * 1.2
    expected_cash_delta = to_settle(acc, inst, -(qty * fill_price + commission_quote))

    @test trade === acc.trades[end]
    @test row.commission_settle ≈ commission_settle atol=1e-12
    @test row.fill_pnl_settle ≈ 0.0 atol=1e-12
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
    @test balance_row.balance ≈ cash_balance(acc, cash_asset(acc, :USD))

    println(DataFrame(tbl))
end

@testitem "equities_table" setup=[TablesTestSetup] begin
    tbl = equities_table(acc)
    equity_schema = Tables.schema(tbl)
    @test equity_schema.names == (:index, :symbol, :equity, :digits)
    equity_row = only(Tables.rows(tbl))
    @test equity_row.symbol == :USD
    @test equity_row.equity ≈ equity(acc, cash_asset(acc, :USD))

    println(DataFrame(tbl))
end
