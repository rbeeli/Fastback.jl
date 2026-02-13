using TestItemRunner

@testitem "liquidate_to_maintenance! closes largest maint contributor first" begin
    using Test, Fastback, Dates

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    deposit!(acc, :USD, 16_000.0)

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

    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency)
    deposit!(acc, :USD, 1_500.0)

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

    er = ExchangeRates()
    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency, margining_style=MarginingStyle.PerCurrency, exchange_rates=er)

    add_asset!(er, cash_asset(acc.ledger, :USD))
    deposit!(acc, :USD, 10_000.0)
    register_cash_asset!(acc.ledger, :EUR)
    add_asset!(er, cash_asset(acc.ledger, :EUR))
    deposit!(acc, :EUR, 200.0)
    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.1)

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

    @test excess_liquidity(acc, cash_asset(acc.ledger, :EUR)) < 0 # only EUR leg is stressed
    @test is_under_maintenance(acc)

    trades = liquidate_to_maintenance!(acc, dt2; commission=0.0)

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
    ledger = CashLedger()
    base_currency = register_cash_asset!(ledger, :USD)
    acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=base_currency, margining_style=MarginingStyle.PerCurrency, exchange_rates=er)
    add_asset!(er, cash_asset(acc.ledger, :USD))
    register_cash_asset!(acc.ledger, :EUR)
    add_asset!(er, cash_asset(acc.ledger, :EUR))
    deposit!(acc, :USD, 0.0)
    deposit!(acc, :EUR, 1_000.0)
    update_rate!(er, cash_asset(acc.ledger, :EUR), cash_asset(acc.ledger, :USD), 1.1) # EUR -> USD

    inst = register_instrument!(acc, Instrument(Symbol("PCUR/FALLBACK"), :PCUR, :USD;
        settle_symbol=:USD,
        margin_symbol=:EUR,
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
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
    @test excess_liquidity(acc, cash_asset(acc.ledger, :USD)) < 0
    @test is_under_maintenance(acc)

    err = try
        liquidate_to_maintenance!(acc, dt2; commission=0.0)
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
