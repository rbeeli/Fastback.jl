using Dates
using TestItemRunner

@testitem "Account reconciliation after sequence" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(
        ;
        broker=FlatFeeBroker(
            ;
            borrow_by_cash=Dict(:USD=>0.0, :EUR=>0.0),
            lend_by_cash=Dict(:USD=>0.05, :EUR=>0.02),
        ),
        funding=AccountFunding.Margined,
        base_currency=base_currency,
        margin_aggregation=MarginAggregation.BaseCurrency,
        exchange_rates=er,
    )

    deposit!(acc, :USD, 10_000.0)
    register_cash_asset!(acc, CashSpec(:EUR))
    deposit!(acc, :EUR, 5_000.0)

    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.1)

    @test Fastback.check_invariants(acc)

    inst_asset = register_instrument!(acc, InstrumentSpec(
        Symbol("ASSET/EURUSD"),
        :ASSET,
        :EUR;
        settle_symbol=:USD,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.2,
        margin_init_short=0.2,
        margin_maint_long=0.1,
        margin_maint_short=0.1,
    ))

    inst_perp = register_instrument!(acc, perpetual_instrument(
        Symbol("PERP/USD"),
        :PERP,
        :USD;
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))

    @test Fastback.check_invariants(acc)

    dt0 = DateTime(2026, 1, 1)
    accrue_interest!(acc, dt0) # initialize accrual clock
    @test Fastback.check_invariants(acc)

    order_asset = Order(oid!(acc), inst_asset, dt0, 100.0, 2.0)
    trade_asset = fill_order!(acc, order_asset; dt=dt0, fill_price=order_asset.price, bid=order_asset.price, ask=order_asset.price, last=order_asset.price)
    @test trade_asset isa Trade
    @test Fastback.check_invariants(acc)

    update_marks!(acc, inst_asset, dt0 + Day(1), 120.0, 120.0, 120.0)
    @test Fastback.check_invariants(acc)

    order_perp = Order(oid!(acc), inst_perp, dt0 + Day(1), 50.0, 1.0)
    trade_perp = fill_order!(acc, order_perp; dt=dt0 + Day(1), fill_price=order_perp.price, bid=order_perp.price, ask=order_perp.price, last=order_perp.price)
    @test trade_perp isa Trade
    @test Fastback.check_invariants(acc)

    update_marks!(acc, inst_perp, dt0 + Day(2), 55.0, 55.0, 55.0)
    @test Fastback.check_invariants(acc)

    accrue_interest!(acc, dt0 + Day(3))
    @test Fastback.check_invariants(acc)
end

@testitem "Invariant audit covers registries, flat state, independent valuation, and history" begin
    using Test, Fastback, Dates

    function empty_account()
        Account(;
            broker=NoOpBroker(),
            funding=AccountFunding.Margined,
            base_currency=CashSpec(:USD),
        )
    end

    mismatched_ledger = empty_account()
    pop!(mismatched_ledger.ledger.equities)
    @test_throws AssertionError Fastback.check_invariants(mismatched_ledger)

    bad_cash_lookup = empty_account()
    bad_cash_lookup.ledger.by_symbol[:USD] = 2
    @test_throws AssertionError Fastback.check_invariants(bad_cash_lookup)

    bad_instrument = empty_account()
    inst = register_instrument!(bad_instrument, spot_instrument(Symbol("BAD_HANDLE/USD"), :BAD_HANDLE, :USD))
    inst.index = 2
    @test_throws AssertionError Fastback.check_invariants(bad_instrument)

    bad_flat = empty_account()
    flat_inst = register_instrument!(bad_flat, spot_instrument(Symbol("BAD_FLAT/USD"), :BAD_FLAT, :USD))
    get_position(bad_flat, flat_inst).avg_entry_price = 1.0
    @test_throws AssertionError Fastback.check_invariants(bad_flat)

    stale = empty_account()
    deposit!(stale, :USD, 1_000.0)
    stale_inst = register_instrument!(stale, spot_instrument(
        Symbol("STALE/USD"),
        :STALE,
        :USD;
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))
    dt = DateTime(2026, 1, 1)
    fill_order!(
        stale,
        Order(oid!(stale), stale_inst, dt, 100.0, 1.0);
        dt=dt,
        fill_price=100.0,
        bid=100.0,
        ask=100.0,
        last=100.0,
    )
    stale_pos = get_position(stale, stale_inst)
    stale_pos.value_quote += 10.0
    stale_pos.value_settle += 10.0
    stale_pos.pnl_quote += 10.0
    stale_pos.pnl_settle += 10.0
    stale.ledger.equities[stale_inst.settle_cash_index] += 10.0
    @test_throws AssertionError Fastback.check_invariants(stale)

    duplicate_trade = empty_account()
    deposit!(duplicate_trade, :USD, 1_000.0)
    duplicate_inst = register_instrument!(duplicate_trade, spot_instrument(Symbol("DUP/USD"), :DUP, :USD))
    fill_order!(
        duplicate_trade,
        Order(oid!(duplicate_trade), duplicate_inst, dt, 100.0, 1.0);
        dt=dt,
        fill_price=100.0,
        bid=100.0,
        ask=100.0,
        last=100.0,
    )
    push!(duplicate_trade.trades, duplicate_trade.trades[1])
    duplicate_trade.trade_count += 1
    @test_throws AssertionError Fastback.check_invariants(duplicate_trade)

    invalid_cashflow = empty_account()
    push!(
        invalid_cashflow.cashflows,
        Cashflow(1, dt, CashflowKind.Other, 2, 1.0, 0),
    )
    invalid_cashflow.cashflow_sequence = 1
    @test_throws AssertionError Fastback.check_invariants(invalid_cashflow)

    nonfinite_ledger = empty_account()
    nonfinite_ledger.ledger.balances[1] = NaN
    @test_throws AssertionError Fastback.check_invariants(nonfinite_ledger)
end
