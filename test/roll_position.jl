using TestItemRunner

@testitem "roll_position! closes old future and opens next with Roll reason" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    deposit!(acc, :USD, 100_000.0)

    front = register_instrument!(acc, future_instrument(
        :MESH25, :MES, :USD;
        margin_requirement=MarginRequirement.FixedPerContract,
        margin_init_long=2_800.0,
        margin_init_short=2_800.0,
        margin_maint_long=2_421.0,
        margin_maint_short=2_421.0,
        multiplier=5.0,
        expiry=DateTime(2025, 3, 21),
    ))
    next = register_instrument!(acc, future_instrument(
        :MESM25, :MES, :USD;
        margin_requirement=MarginRequirement.FixedPerContract,
        margin_init_long=2_800.0,
        margin_init_short=2_800.0,
        margin_maint_long=2_421.0,
        margin_maint_short=2_421.0,
        multiplier=5.0,
        expiry=DateTime(2025, 6, 20),
    ))

    dt_open = DateTime(2025, 3, 3)
    fill_order!(
        acc,
        Order(oid!(acc), front, dt_open, 5_000.25, 3.0);
        dt=dt_open,
        fill_price=5_000.25,
        bid=5_000.0,
        ask=5_000.25,
        last=5_000.125,
    )

    dt_roll = DateTime(2025, 3, 13)
    close_trade, open_trade = roll_position!(
        acc,
        front,
        next,
        dt_roll;
        close_fill_price=4_998.75,
        close_bid=4_998.75,
        close_ask=4_999.00,
        close_last=4_998.875,
        open_fill_price=5_003.00,
        open_bid=5_002.75,
        open_ask=5_003.00,
        open_last=5_002.875,
    )

    @test close_trade isa Trade
    @test open_trade isa Trade
    @test close_trade.reason == TradeReason.Roll
    @test open_trade.reason == TradeReason.Roll
    @test close_trade.order.inst === front
    @test open_trade.order.inst === next
    @test close_trade.date == dt_roll
    @test open_trade.date == dt_roll
    @test close_trade.fill_qty == -3.0
    @test open_trade.fill_qty == 3.0
    @test get_position(acc, front).quantity == 0.0
    @test get_position(acc, next).quantity == 3.0
end

@testitem "roll_position! is a no-op when source instrument is flat" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    deposit!(acc, :USD, 10_000.0)

    front = register_instrument!(acc, future_instrument(
        :MESH25, :MES, :USD;
        margin_requirement=MarginRequirement.FixedPerContract,
        margin_init_long=2_800.0,
        margin_init_short=2_800.0,
        margin_maint_long=2_421.0,
        margin_maint_short=2_421.0,
        multiplier=5.0,
        expiry=DateTime(2025, 3, 21),
    ))
    next = register_instrument!(acc, future_instrument(
        :MESM25, :MES, :USD;
        margin_requirement=MarginRequirement.FixedPerContract,
        margin_init_long=2_800.0,
        margin_init_short=2_800.0,
        margin_maint_long=2_421.0,
        margin_maint_short=2_421.0,
        multiplier=5.0,
        expiry=DateTime(2025, 6, 20),
    ))

    dt_roll = DateTime(2025, 3, 13)
    close_trade, open_trade = roll_position!(
        acc,
        front,
        next,
        dt_roll;
        close_fill_price=4_998.75,
        open_fill_price=5_003.00,
    )

    @test close_trade === nothing
    @test open_trade === nothing
    @test isempty(acc.trades)
end

@testitem "roll_position! enforces settlement and margin profile match" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    register_cash_asset!(acc, CashSpec(:USDT))
    deposit!(acc, :USD, 100_000.0)

    front = register_instrument!(acc, future_instrument(
        :MESH25, :MES, :USD;
        margin_requirement=MarginRequirement.FixedPerContract,
        margin_init_long=2_800.0,
        margin_init_short=2_800.0,
        margin_maint_long=2_421.0,
        margin_maint_short=2_421.0,
        multiplier=5.0,
        expiry=DateTime(2025, 3, 21),
    ))

    mismatched_settle = register_instrument!(acc, future_instrument(
        :MESM25_SETTLE, :MES, :USD;
        margin_requirement=MarginRequirement.FixedPerContract,
        margin_init_long=2_800.0,
        margin_init_short=2_800.0,
        margin_maint_long=2_421.0,
        margin_maint_short=2_421.0,
        settle_symbol=:USDT,
        margin_symbol=:USDT,
        multiplier=5.0,
        expiry=DateTime(2025, 6, 20),
    ))

    mismatched_margin = register_instrument!(acc, future_instrument(
        :MESM25_MARGIN, :MES, :USD;
        margin_requirement=MarginRequirement.FixedPerContract,
        margin_init_long=2_800.0,
        margin_init_short=2_800.0,
        margin_maint_long=2_421.0,
        margin_maint_short=2_421.0,
        margin_symbol=:USDT,
        multiplier=5.0,
        expiry=DateTime(2025, 6, 20),
    ))

    mismatched_settlement = register_instrument!(acc, spot_instrument(
        :MES_SPOT, :MES, :USD;
        margin_requirement=MarginRequirement.FixedPerContract,
        margin_init_long=2_800.0,
        margin_init_short=2_800.0,
        margin_maint_long=2_421.0,
        margin_maint_short=2_421.0,
        multiplier=5.0,
    ))

    mismatched_margin_requirement = register_instrument!(acc, future_instrument(
        :MESM25_IMR, :MES, :USD;
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.10,
        margin_init_short=0.10,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        multiplier=5.0,
        expiry=DateTime(2025, 6, 20),
    ))

    dt_open = DateTime(2025, 3, 3)
    fill_order!(
        acc,
        Order(oid!(acc), front, dt_open, 5_000.25, 1.0);
        dt=dt_open,
        fill_price=5_000.25,
        bid=5_000.0,
        ask=5_000.25,
        last=5_000.125,
    )

    dt_roll = DateTime(2025, 3, 13)
    @test_throws ArgumentError roll_position!(
        acc,
        front,
        mismatched_settle,
        dt_roll;
        close_fill_price=4_998.75,
        open_fill_price=5_003.00,
    )
    @test_throws ArgumentError roll_position!(
        acc,
        front,
        mismatched_margin,
        dt_roll;
        close_fill_price=4_998.75,
        open_fill_price=5_003.00,
    )
    @test_throws ArgumentError roll_position!(
        acc,
        front,
        mismatched_settlement,
        dt_roll;
        close_fill_price=4_998.75,
        open_fill_price=5_003.00,
    )
    @test_throws ArgumentError roll_position!(
        acc,
        front,
        mismatched_margin_requirement,
        dt_roll;
        close_fill_price=4_998.75,
        open_fill_price=5_003.00,
    )
end
