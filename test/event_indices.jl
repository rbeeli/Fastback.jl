using TestItemRunner

@testitem "short indices and proceeds cache follow fills, FX and corporate actions" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=FlatFeeBroker(; lend_by_cash=Dict(:USD => 0.05)),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        track_trades=false,
    )
    register_cash_asset!(acc, CashSpec(:EUR))
    update_rate!(acc, :EUR, :USD, 1.2)
    deposit!(acc, :USD, 100_000.0)
    a = register_instrument!(acc, spot_instrument(:A, :A, :EUR;
        settle_symbol=:USD, short_borrow_rate=0.12))
    b = register_instrument!(acc, spot_instrument(:B, :B, :USD))
    dt = DateTime(2026, 1, 1)

    function fill!(
        acc,
        inst,
        dt,
        price,
        qty,
    )
        fill_order!(acc, Order(oid!(acc), inst, dt, price, qty);
            dt=dt, fill_price=price, bid=price, ask=price, last=price)
    end

    fill!(acc, b, dt, 50.0, -3.0)
    fill!(acc, a, dt, 100.0, -4.0)
    state = acc._event_state
    @test state.short_positions == [a.index, b.index]
    @test state.borrow_positions == [a.index]
    accrue_interest!(acc, dt)
    accrue_interest!(acc, dt + Day(1))
    @test acc.ledger.short_proceeds_by_cash_buffer[1] ≈ 630.0
    @test !state.short_proceeds_dirty

    # FX translation of an existing short does not change its entry proceeds.
    process_step!(acc, dt + Day(2);
        fx_updates=[FXUpdate(cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.3)])
    @test !state.short_proceeds_dirty
    @test acc.ledger.short_proceeds_by_cash_buffer[1] ≈ 630.0
    @test Fastback.check_invariants(acc)

    apply_spot_corporate_action!(acc, a, dt + Day(2); split_factor=2.0)
    @test state.short_proceeds_dirty
    accrue_interest!(acc, dt + Day(3))
    @test acc.ledger.short_proceeds_by_cash_buffer[1] ≈ 630.0
    @test state.borrow_positions == [a.index]
    @test Fastback.check_invariants(acc)

    @test_throws OrderRejectError fill!(acc, a, dt + Day(3), 50.0, 1e9)
    @test !state.short_proceeds_dirty
    @test state.short_positions == [a.index, b.index]
    fill!(acc, a, dt + Day(3), 50.0, 8.0)
    @test state.short_positions == [b.index]
    @test isempty(state.borrow_positions)
    fill!(acc, b, dt + Day(3), 50.0, 6.0)
    @test isempty(state.short_positions)
    accrue_interest!(acc, dt + Day(4))
    @test all(iszero, acc.ledger.short_proceeds_by_cash_buffer)
    @test Fastback.check_invariants(acc)

    fill!(acc, a, dt + Day(4), 50.0, -2.0)
    @test state.short_positions == state.borrow_positions == [a.index]
    @test Fastback.check_invariants(acc)
end

@testitem "expiry index tracks exposure and preserves registration order across dates" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    deposit!(acc, :USD, 1e6)
    dt = DateTime(2026, 1, 1)

    function future!(acc, symbol, expiry)
        register_instrument!(acc, future_instrument(symbol, symbol, :USD;
            expiry=expiry, margin_requirement=MarginRequirement.FixedPerContract,
            margin_init_long=10.0, margin_init_short=10.0,
            margin_maint_long=5.0, margin_maint_short=5.0))
    end

    late = future!(acc, :LATE, dt + Day(4))
    early = future!(acc, :EARLY, dt + Day(2))
    flat = future!(acc, :FLAT, dt + Day(1))

    # A query with no exposure must not consume future eligibility or move time.
    @test isempty(process_expiries!(acc, dt + Day(10)))
    @test acc.last_event_dt == DateTime(0)
    for inst in (late, early, flat)
        fill_order!(acc, Order(oid!(acc), inst, dt, 100.0, 1.0);
            dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    end
    @test sort(acc._event_state.expiry_positions; by=i -> acc.positions[i].inst.spec.expiry) == [flat.index, early.index, late.index]
    fill_order!(acc, Order(oid!(acc), flat, dt, 100.0, -1.0);
        dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    @test acc._event_state.expiry_positions == [early.index, late.index]
    @test isempty(process_expiries!(acc, dt + Day(1)))
    @test Fastback.check_invariants(acc)

    trades = process_expiries!(acc, dt + Day(5))
    @test [t.order.inst.index for t in trades] == [late.index, early.index]
    @test isempty(acc._event_state.expiry_positions)
    @test Fastback.check_invariants(acc)

    newer = future!(acc, :NEW, dt + Day(7))
    fill_order!(acc, Order(oid!(acc), newer, dt + Day(5), 100.0, 1.0);
        dt=dt + Day(5), fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    settle_expiry!(acc, newer, dt + Day(7))
    @test isempty(acc._event_state.expiry_positions)
    @test Fastback.check_invariants(acc)
end

@testitem "indexed FX refresh matches full refresh for split routes and option groups" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    deposit!(acc, :USD, 1e6)
    for symbol in (:EUR, :CHF, :GBP)
        register_cash_asset!(acc, CashSpec(symbol))
    end
    for (from, to, rate) in ((:EUR, :USD, 1.2), (:EUR, :CHF, 1.1), (:USD, :CHF, 0.9), (:GBP, :USD, 1.3))
        update_rate!(acc, from, to, rate)
    end
    dt = DateTime(2026, 1, 1)
    spot = register_instrument!(acc, spot_instrument(:SPOT, :SPOT, :EUR;
        settle_symbol=:USD, margin_symbol=:CHF))
    vm = register_instrument!(acc, future_instrument(:VM, :VM, :EUR;
        settle_symbol=:USD, margin_symbol=:CHF, expiry=dt + Day(30),
        margin_requirement=MarginRequirement.FixedPerContract,
        margin_init_long=10.0, margin_init_short=10.0,
        margin_maint_long=5.0, margin_maint_short=5.0))
    long_call = register_instrument!(acc, option_instrument(:C100, :UNDERLYING, :EUR;
        strike=100.0, expiry=dt + Day(30), right=OptionRight.Call,
        settle_symbol=:USD, margin_symbol=:CHF))
    short_call = register_instrument!(acc, option_instrument(:C110, :UNDERLYING, :EUR;
        strike=110.0, expiry=dt + Day(30), right=OptionRight.Call,
        settle_symbol=:USD, margin_symbol=:CHF))
    for (inst, qty, price) in ((spot, 2.0, 100.0), (vm, 1.0, 100.0), (long_call, 1.0, 4.0), (short_call, -1.0, 2.0))
        underlying = inst.spec.contract_kind == ContractKind.Option ? 105.0 : NaN
        fill_order!(acc, Order(oid!(acc), inst, dt, price, qty);
            dt=dt, fill_price=price, bid=price, ask=price, last=price, underlying_price=underlying)
    end
    @test !haskey(acc._event_state.fx_dependents, (1, 4))
    @test all(d.index != vm.index for deps in values(acc._event_state.fx_dependents) for d in deps.positions)
    reference = deepcopy(acc)

    routes = (
        [(:GBP, :USD, 1.4)],
        [(:EUR, :USD, 1.3)],
        [(:EUR, :CHF, 1.2)],
        [(:EUR, :USD, 1.5), (:EUR, :CHF, 1.3), (:USD, :EUR, 0.8)],
    )
    for (i, changes) in enumerate(routes)
        updates = [FXUpdate(cash_asset(acc, from), cash_asset(acc, to), rate) for (from, to, rate) in changes]
        process_step!(acc, dt + Day(i); fx_updates=updates,
            accrue_interest=false, accrue_borrow_fees=false, expiries=false)
        for (from, to, rate) in changes
            update_rate!(reference.exchange_rates, cash_asset(reference, from), cash_asset(reference, to), rate)
        end
        Fastback._revalue_fx_caches!(reference)
        for field in (:balances, :equities, :init_margin_used, :maint_margin_used)
            @test getfield(acc.ledger, field) ≈ getfield(reference.ledger, field)
        end
        for (actual, expected) in zip(acc.positions, reference.positions)
            @test actual.value_settle ≈ expected.value_settle
            @test actual.pnl_settle ≈ expected.pnl_settle
            @test actual.init_margin_settle ≈ expected.init_margin_settle
        end
        @test all(iszero, acc._event_state.fx_effects)
        @test Fastback.check_invariants(acc)
    end
end

@testitem "active FX dependencies follow closes, reversals and reordered opens" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD), track_trades=false, track_cashflows=false)
    deposit!(acc, :USD, 1e6)
    for sym in (:EUR, :CHF)
        register_cash_asset!(acc, CashSpec(sym))
    end
    update_rate!(acc, :EUR, :USD, 1.2)
    update_rate!(acc, :EUR, :CHF, 1.1)
    update_rate!(acc, :CHF, :USD, 1.0)
    instruments = [register_instrument!(acc, spot_instrument(Symbol("ACTIVE", i), :A, :EUR;
        settle_symbol=:USD, margin_symbol=isodd(i) ? :USD : :CHF)) for i in 1:128]
    dt = DateTime(2026, 1, 1)
    changes = ((128, 1.0), (2, -1.0), (1, 1.0), (128, -1.0), (2, 2.0),
        (1, -1.0), (2, -1.0), (1, 1.0), (128, 1.0), (2, 1.0))
    for (step, (i, qty)) in enumerate(changes)
        event_dt = dt + Minute(step)
        inst = instruments[i]
        fill_order!(acc, Order(oid!(acc), inst, event_dt, 100.0, qty);
            dt=event_dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
        reference = deepcopy(acc)
        updates = [FXUpdate(cash_asset(acc, :EUR), acc.base_currency, 1.3),
            FXUpdate(cash_asset(acc, :EUR), cash_asset(acc, :CHF), 1.15)]
        process_step!(acc, event_dt; fx_updates=updates, accrue_interest=false, accrue_borrow_fees=false)
        update_rate!(reference.exchange_rates, cash_asset(reference, :EUR), reference.base_currency, 1.3)
        update_rate!(reference.exchange_rates, cash_asset(reference, :EUR), cash_asset(reference, :CHF), 1.15)
        Fastback._revalue_fx_caches!(reference)
        @test acc.ledger.equities ≈ reference.ledger.equities
        @test acc.ledger.init_margin_used ≈ reference.ledger.init_margin_used
        @test length(acc._event_state.open_positions) <= 3
        @test all(length(d.positions) <= 3 for d in values(acc._event_state.fx_dependents))
        @test Fastback.check_invariants(acc)
    end
end

@testitem "expiry heap handles arbitrary churn and partial bulk settlement" begin
    using Test, Fastback, Dates, Random

    rng = MersenneTwister(17)
    dt = DateTime(2026, 1, 1)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD), track_trades=false, track_cashflows=false)
    deposit!(acc, :USD, 1e6)
    instruments = [register_instrument!(acc, future_instrument(Symbol("HEAP", i), :F, :USD;
        expiry=dt + Day(mod(17i, 64) + 1), margin_requirement=MarginRequirement.FixedPerContract,
        margin_init_long=1.0, margin_init_short=1.0,
        margin_maint_long=0.5, margin_maint_short=0.5)) for i in 1:64]
    for i in 1:256
        inst = rand(rng, instruments)
        qty = get_position(acc, inst).quantity == 0.0 ? 1.0 : -1.0
        fill_order!(acc, Order(oid!(acc), inst, dt, 100.0, qty);
            dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
        @test Fastback.check_invariants(acc)
    end
    for day in (1, 16, 32, 64)
        process_step!(acc, dt + Day(day))
        @test all(pos.quantity == 0.0 || pos.inst.spec.expiry > dt + Day(day) for pos in acc.positions)
        @test Fastback.check_invariants(acc)
    end
    @test isempty(acc._event_state.open_positions)

    # A later option failure must leave the successful future settlement and
    # the remaining option membership consistent, even during bulk cleanup.
    failed = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD), track_trades=false)
    deposit!(failed, :USD, 1e6)
    future = register_instrument!(failed, future_instrument(:F, :F, :USD;
        expiry=dt + Day(1), margin_requirement=MarginRequirement.FixedPerContract,
        margin_init_long=1.0, margin_init_short=1.0, margin_maint_long=0.5, margin_maint_short=0.5))
    option = register_instrument!(failed, option_instrument(:C, :U, :USD;
        strike=100.0, expiry=dt + Day(1), right=OptionRight.Call))
    for inst in (future, option)
        fill_order!(failed, Order(oid!(failed), inst, dt, 100.0, 1.0);
            dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    end
    @test_throws ArgumentError process_step!(failed, dt + Day(1))
    @test failed.poisoned
    @test !failed._event_state.bulk_expiry
    @test get_position(failed, future).quantity == 0.0
    @test get_position(failed, option).quantity == 1.0
    @test failed._event_state.expiry_positions == [option.index]
    @test Fastback.check_invariants(failed)
end
