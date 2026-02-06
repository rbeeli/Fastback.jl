using TestItemRunner

@testitem "liquidate_to_maintenance! closes largest maint contributor first" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 16_000.0)

    inst_big = register_instrument!(acc, Instrument(Symbol("BIG/USD"), :BIG, :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.2, margin_init_short=0.2,
        margin_maint_long=0.1, margin_maint_short=0.1))

    inst_small = register_instrument!(acc, Instrument(Symbol("SML/USD"), :SML, :USD;
        margin_mode=MarginMode.PercentNotional,
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

    trades = liquidate_to_maintenance!(acc, dt2; commission=0.0)

    @test !is_under_maintenance(acc)
    @test length(trades) == 1
    @test trades[1].order.inst === inst_big
    @test trades[1].reason == TradeReason.Liquidation
    @test get_position(acc, inst_big).quantity == 0.0
    @test get_position(acc, inst_small).quantity == -10.0
end

@testitem "liquidate_to_maintenance! forwards commission_pct" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 1_500.0)

    inst = register_instrument!(acc, Instrument(Symbol("RISK/USD"), :RISK, :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1, margin_init_short=0.1,
        margin_maint_long=0.1, margin_maint_short=0.1))

    dt = DateTime(2024, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt, 100.0, 100.0); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    dt2 = dt + Day(1)
    update_marks!(acc, get_position(acc, inst), dt2, 90.0, 90.0, 90.0)

    # Account is under maintenance after an adverse mark.
    @test is_under_maintenance(acc)

    trades = liquidate_to_maintenance!(acc, dt2; commission=1.0, commission_pct=0.02)

    @test length(trades) == 1
    @test trades[1].commission_settle ≈ 181.0 # 1 fixed + 2% of 90*100
    @test !is_under_maintenance(acc)
    @test get_position(acc, inst).quantity == 0.0
end

@testitem "per-currency liquidation targets offending currency" begin
    using Test, Fastback, Dates

    er = SpotExchangeRates()
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD, margining_style=MarginingStyle.PerCurrency, exchange_rates=er)

    usd = Cash(:USD)
    eur = Cash(:EUR)
    deposit!(acc, usd, 10_000.0)
    deposit!(acc, eur, 200.0)
    update_rate!(er, eur, usd, 1.1)

    inst_eur = register_instrument!(acc, Instrument(Symbol("PER/EUR"), :PER, :EUR;
        settle_symbol=:EUR,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.3, margin_init_short=0.3,
        margin_maint_long=0.2, margin_maint_short=0.2))

    inst_usd = register_instrument!(acc, Instrument(Symbol("PER/USD"), :PER, :USD;
        settle_symbol=:USD,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.3, margin_init_short=0.3,
        margin_maint_long=0.2, margin_maint_short=0.2))

    dt = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst_eur, dt, 100.0, 5.0); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    fill_order!(acc, Order(oid!(acc), inst_usd, dt, 100.0, 100.0); dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)

    dt2 = dt + Hour(1)
    update_marks!(acc, inst_eur, dt2, 70.0, 70.0, 70.0)

    @test excess_liquidity(acc, :EUR) < 0 # only EUR leg is stressed
    @test is_under_maintenance(acc)

    trades = liquidate_to_maintenance!(acc, dt2; commission=0.0)

    @test length(trades) == 1
    @test trades[1].order.inst === inst_eur
    @test !is_under_maintenance(acc)
    @test get_position(acc, inst_eur).quantity == 0.0
    @test get_position(acc, inst_usd).quantity == 100.0
    @test Fastback.check_invariants(acc)
end
