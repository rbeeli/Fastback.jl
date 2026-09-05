using Dates
using TestItemRunner

@testitem "forward event loop and fresh orders allocate zero without history" begin
    using Test, Fastback, Dates

    function drive!(acc, marks)
        dt = acc.last_event_dt
        inst = first(acc.positions).inst

        for i in 1:64
            dt += Millisecond(1)
            price = 100.0 + (i % 2)
            marks[1] = MarkUpdate(inst.index, price, price, price)
            process_step!(acc, dt; marks=marks)
            direction = inst.spec.short_borrow_rate > 0.0 ? -1.0 : 1.0
            qty = isodd(i) ? direction : -direction
            order = Order(oid!(acc), inst, dt, price, qty)
            fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price)
        end
        nothing
    end

    for kind in (:spot, :future, :short, :option)
        acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined,
            base_currency=CashSpec(:USD), track_trades=false, track_cashflows=false)
        deposit!(acc, :USD, 1e6)
        dt = DateTime(2026, 1, 1)
        spec = if kind == :future
            future_instrument(:PERF_VM, :VM, :USD;
                expiry=dt + Day(365), margin_requirement=MarginRequirement.PercentNotional,
                margin_init_long=0.1, margin_init_short=0.1,
                margin_maint_long=0.05, margin_maint_short=0.05)
        elseif kind == :option
            option_instrument(:PERF_OPTION, :UNDERLYING, :USD;
                strike=100.0, expiry=dt + Day(365), right=OptionRight.Call)
        else
            spot_instrument(:PERF_FRESH, :FRESH, :USD;
                short_borrow_rate=kind == :short ? 0.1 : 0.0)
        end
        inst = register_instrument!(acc, spec)
        for i in 1:1024
            register_instrument!(acc, spot_instrument(Symbol("INACTIVE", i), :INACTIVE, :USD))
        end
        process_step!(acc, dt)
        marks = [MarkUpdate(inst.index, 100.0, 100.0, 100.0)]
        drive!(acc, marks)
        drive!(acc, marks)
        alloc = @allocated drive!(acc, marks)
        @test alloc == 0
        @test acc.last_event_dt == acc.last_interest_dt
        @test isempty(acc._event_state.short_positions)
        @test isempty(acc._event_state.borrow_positions)
        @test isempty(acc._event_state.expiry_positions)
        @test Fastback.check_invariants(acc)
    end
end

@testitem "sparse and overlapping FX updates reuse account buffers" begin
    using Test, Fastback, Dates

    function drive_fx!(acc, updates)
        for _ in 1:16
            process_step!(acc, acc.last_event_dt + Millisecond(1); fx_updates=updates)
        end
        nothing
    end

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD), track_trades=false, track_cashflows=false)
    deposit!(acc, :USD, 1e6)
    for sym in (:EUR, :CHF, :GBP)
        register_cash_asset!(acc, CashSpec(sym))
    end
    update_rate!(acc, :EUR, :USD, 1.2)
    update_rate!(acc, :EUR, :CHF, 1.1)
    update_rate!(acc, :CHF, :USD, 1.0)
    inst = register_instrument!(acc, spot_instrument(:FX_OPEN, :OPEN, :EUR;
        settle_symbol=:USD, margin_symbol=:CHF))
    for i in 1:1024
        register_instrument!(acc, spot_instrument(Symbol("FX_INACTIVE", i), :INACTIVE, :USD))
    end
    dt = DateTime(2026, 1, 1)
    fill_order!(acc, Order(oid!(acc), inst, dt, 100.0, 1.0);
        dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    for i in 1:96
        quote_symbol = isodd(i) ? :EUR : :CHF
        other = register_instrument!(acc, spot_instrument(Symbol("FX_OTHER", i), :OTHER, quote_symbol;
            settle_symbol=:USD))
        fill_order!(acc, Order(oid!(acc), other, dt, 100.0, 1.0);
            dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    end
    usd, eur, chf, gbp = (cash_asset(acc, sym) for sym in (:USD, :EUR, :CHF, :GBP))

    for updates in ([FXUpdate(gbp, usd, 1.3)], [FXUpdate(eur, usd, 1.25)],
                    [FXUpdate(eur, usd, 1.3), FXUpdate(eur, chf, 1.2),
                     FXUpdate(chf, usd, 1.05), FXUpdate(usd, eur, 0.8)])
        drive_fx!(acc, updates)
        drive_fx!(acc, updates)
        alloc = @allocated drive_fx!(acc, updates)
        @test alloc == 0
        @test length(acc._event_state.fx_positions) <= 97
        @test Fastback.check_invariants(acc)
    end
end

@testitem "update_marks! allocates ~0 after warmup" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("PERF/USD"), :PERF, :USD))
    pos = get_position(acc, inst)

    dt0 = DateTime(2026, 1, 1)
    dt1 = dt0 + Day(1)
    update_marks!(acc, pos, dt0, 100.0, 100.0, 100.0) # warm compile + ensure exposure state

    # warm twice to eliminate first-call cache touch
    update_marks!(acc, pos, dt1, 101.0, 101.0, 101.0)
    alloc = @allocated update_marks!(acc, pos, dt1, 101.0, 101.0, 101.0)
    @test alloc == 0
end

@testitem "Cashflow is bits-stored for inline vector storage" begin
    using Test, Fastback, Dates

    @test isbitstype(Cashflow{DateTime})
end

@testitem "fill_order! allocations are bounded after warmup" begin
    using Test, Fastback, Dates

    function setup_account()
        base_currency=CashSpec(:USD)
        acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
        deposit!(acc, :USD, 10_000.0)
        inst = register_instrument!(acc, spot_instrument(Symbol("PERFFILL/USD"), :PERFFILL, :USD))
        dt0 = DateTime(2026, 1, 1)
        update_marks!(acc, get_position(acc, inst), dt0, 100.0, 100.0, 100.0)
        fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
        fill_order!(acc, Order(oid!(acc), inst, dt0 + Day(1), 101.0, 0.5); dt=dt0 + Day(1), fill_price=101.0, bid=101.0, ask=101.0, last=101.0)
        sizehint!(acc.trades, length(acc.trades) + 4)
        return acc, inst, dt0
    end

    acc_kw, inst_kw, dt0_kw = setup_account()

    trade_alloc = let
        o = Order(0, inst_kw, dt0_kw, 0.0, 0.0)
        Trade(o, 0, dt0_kw, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, TradeReason.Normal)
        @allocated Trade(o, 1, dt0_kw, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, TradeReason.Normal)
    end

    order_kw1 = Order(oid!(acc_kw), inst_kw, dt0_kw + Day(2), 101.0, -0.25)
    fill_order!(acc_kw, order_kw1; dt=dt0_kw + Day(2), fill_price=101.0, bid=101.0, ask=101.0, last=101.0)
    order_kw2 = Order(oid!(acc_kw), inst_kw, dt0_kw + Day(3), 101.0, -0.25)
    fill_order!(acc_kw, order_kw2; dt=dt0_kw + Day(3), fill_price=101.0, bid=101.0, ask=101.0, last=101.0)
    order_kw3 = Order(oid!(acc_kw), inst_kw, dt0_kw + Day(4), 101.0, -0.25)

    kw_alloc = @allocated fill_order!(acc_kw, order_kw3; dt=dt0_kw + Day(4), fill_price=101.0, bid=101.0, ask=101.0, last=101.0)

    # Bound the kw path after warmup; allow small overhead above Trade allocation.
    @test trade_alloc == 144
    @test kw_alloc <= trade_alloc + 256
end

@testitem "process_step! reuses buffers (no allocations) after warmup" begin
    using Test, Fastback, Dates

    alloc = let
        base_currency=CashSpec(:USD)
        acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
        deposit!(acc, :USD, 10_000.0)
        inst = register_instrument!(acc, spot_instrument(Symbol("PERFSTEP/USD"), :PERFSTEP, :USD))
        pos = get_position(acc, inst)

        dt0 = DateTime(2026, 1, 1)
        dt1 = dt0 + Day(1)
        update_marks!(acc, pos, dt0, 100.0, 100.0, 100.0)
        fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
        update_marks!(acc, pos, dt1, 101.0, 101.0, 101.0)

        marks = [MarkUpdate(inst.index, 102.0, 102.0, 102.0)]
        # double warmup avoids the single tiny allocation seen on the first post-setup call
        process_step!(acc, dt1; marks=marks, accrue_interest=false, accrue_borrow_fees=false, expiries=false, liquidate=false)
        process_step!(acc, dt1; marks=marks, accrue_interest=false, accrue_borrow_fees=false, expiries=false, liquidate=false)
        @allocated process_step!(acc, dt1; marks=marks, accrue_interest=false, accrue_borrow_fees=false, expiries=false, liquidate=false)
    end
    @test alloc == 0  # deterministic zero after warmup
end

@testitem "multi-mark process_step! does not allocate with a large account" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        track_trades=false,
        track_cashflows=false,
    )
    insts = Instrument{DateTime}[]
    sizehint!(insts, 256)
    for i in 1:256
        push!(insts, register_instrument!(
            acc,
            spot_instrument(Symbol("PERFSTEP_$(i)/USD"), Symbol("PERFSTEP_$(i)"), :USD),
        ))
    end

    marks = MarkUpdate[
        MarkUpdate(insts[1].index, 100.0, 100.0, 100.0),
        MarkUpdate(insts[end].index, 101.0, 101.0, 101.0),
    ]
    dt = DateTime(2026, 1, 1)
    process_step!(acc, dt; marks=marks, expiries=false, accrue_interest=false, accrue_borrow_fees=false)
    process_step!(acc, dt; marks=marks, expiries=false, accrue_interest=false, accrue_borrow_fees=false)

    alloc = let acc=acc, dt=dt, marks=marks
        @allocated process_step!(
            acc,
            dt;
            marks=marks,
            expiries=false,
            accrue_interest=false,
            accrue_borrow_fees=false,
        )
    end
    @test alloc == 0
end

@testitem "ordinary fill planning is allocation-free without history" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        track_trades=false,
        track_cashflows=false,
    )
    deposit!(acc, :USD, 10_000.0)
    inst = register_instrument!(acc, spot_instrument(Symbol("PERFPLAN/USD"), :PERFPLAN, :USD))
    dt = DateTime(2026, 1, 1)
    buy = Order(1, inst, dt, 100.0, 1.0)
    sell = Order(2, inst, dt, 100.0, -1.0)

    function roundtrip!(acc, buy, sell, dt)
        fill_order!(acc, buy; dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
        fill_order!(acc, sell; dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
        nothing
    end

    roundtrip!(acc, buy, sell, dt)
    roundtrip!(acc, buy, sell, dt)
    @test (@allocated roundtrip!(acc, buy, sell, dt)) == 0
end

@testitem "process_step! with expiries=true avoids empty expiry allocations after warmup" begin
    using Test, Fastback, Dates

    alloc = let
        base_currency=CashSpec(:USD)
        acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
        deposit!(acc, :USD, 10_000.0)
        inst = register_instrument!(acc, spot_instrument(Symbol("PERFEXP/USD"), :PERFEXP, :USD))
        pos = get_position(acc, inst)

        dt0 = DateTime(2026, 1, 1)
        update_marks!(acc, pos, dt0, 100.0, 100.0, 100.0)

        # warm twice to eliminate first-call cache touch
        process_step!(acc, dt0; marks=nothing, fx_updates=nothing, funding=nothing, accrue_interest=false, accrue_borrow_fees=false, expiries=true, liquidate=false)
        process_step!(acc, dt0; marks=nothing, fx_updates=nothing, funding=nothing, accrue_interest=false, accrue_borrow_fees=false, expiries=true, liquidate=false)
        @allocated process_step!(acc, dt0; marks=nothing, fx_updates=nothing, funding=nothing, accrue_interest=false, accrue_borrow_fees=false, expiries=true, liquidate=false)
    end
    @test alloc == 0
end

@testitem "option margin recompute reuses scratch buffers after warmup" begin
    using Test, Fastback, Dates

    acc = Account(;
        time_type=Date,
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
    )
    deposit!(acc, :USD, 10_000.0)

    dt = Date(2026, 1, 5)
    expiry = Date(2026, 2, 20)
    long_put = register_instrument!(acc, option_instrument(:PERFOPT_P90, :AAPL, :USD;
        strike=90.0,
        expiry=expiry,
        right=OptionRight.Put,
        time_type=Date,
    ))
    short_put = register_instrument!(acc, option_instrument(:PERFOPT_P100, :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Put,
        time_type=Date,
    ))
    short_call = register_instrument!(acc, option_instrument(:PERFOPT_C110, :AAPL, :USD;
        strike=110.0,
        expiry=expiry,
        right=OptionRight.Call,
        time_type=Date,
    ))
    long_call = register_instrument!(acc, option_instrument(:PERFOPT_C120, :AAPL, :USD;
        strike=120.0,
        expiry=expiry,
        right=OptionRight.Call,
        time_type=Date,
    ))

    fill_option_strategy!(
        acc,
        Order{Date}[
            Order(oid!(acc), long_put, dt, 1.0, 1.0),
            Order(oid!(acc), short_put, dt, 3.0, -1.0),
            Order(oid!(acc), short_call, dt, 3.0, -1.0),
            Order(oid!(acc), long_call, dt, 1.0, 1.0),
        ];
        dt=dt,
        fill_prices=Price[1.0, 3.0, 3.0, 1.0],
        bids=Price[1.0, 3.0, 3.0, 1.0],
        asks=Price[1.0, 3.0, 3.0, 1.0],
        lasts=Price[1.0, 3.0, 3.0, 1.0],
        underlying_price=105.0,
    )

    Fastback.recompute_option_margins!(acc)
    Fastback.recompute_option_margins!(acc)
    alloc = @allocated Fastback.recompute_option_margins!(acc)
    @test alloc == 0
end

@testitem "single option fill_order! allocation stays bounded after warmup" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        track_trades=false,
    )
    deposit!(acc, :USD, 100_000.0)
    dt = DateTime(2026, 1, 5)
    call = register_instrument!(acc, option_instrument(:PERF_FILL_C100, :AAPL, :USD;
        strike=100.0,
        expiry=DateTime(2026, 2, 20),
        right=OptionRight.Call,
    ))

    fill_order!(acc, Order(oid!(acc), call, dt, 1.0, 1.0);
        dt=dt,
        fill_price=1.0,
        bid=1.0,
        ask=1.0,
        last=1.0,
    )
    fill_order!(acc, Order(oid!(acc), call, dt + Day(1), 1.0, 1.0);
        dt=dt + Day(1),
        fill_price=1.0,
        bid=1.0,
        ask=1.0,
        last=1.0,
    )

    order = Order(oid!(acc), call, dt + Day(2), 1.0, 1.0)
    alloc = @allocated fill_order!(acc, order;
        dt=dt + Day(2),
        fill_price=1.0,
        bid=1.0,
        ask=1.0,
        last=1.0,
    )
    @test alloc <= 512
end

@testitem "option strategy fill allocation stays bounded after warmup" begin
    using Test, Fastback, Dates

    acc = Account(;
        broker=NoOpBroker(),
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        track_trades=false,
    )
    deposit!(acc, :USD, 100_000.0)
    dt = DateTime(2026, 1, 5)
    expiry = DateTime(2026, 2, 20)
    long_call = register_instrument!(acc, option_instrument(:PERF_STRAT_C100, :AAPL, :USD;
        strike=100.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))
    short_call = register_instrument!(acc, option_instrument(:PERF_STRAT_C105, :AAPL, :USD;
        strike=105.0,
        expiry=expiry,
        right=OptionRight.Call,
    ))

    fill_prices = [5.0, 2.0]
    bids = [5.0, 2.0]
    asks = [5.0, 2.0]
    lasts = [5.0, 2.0]
    for offset in 0:2
        orders = [
            Order(oid!(acc), long_call, dt + Day(offset), 5.0, 1.0),
            Order(oid!(acc), short_call, dt + Day(offset), 2.0, -1.0),
        ]
        Fastback._fill_option_strategy!(
            acc,
            orders,
            dt + Day(offset),
            fill_prices,
            bids,
            asks,
            lasts,
            nothing,
            nothing,
            TradeReason.Normal,
            100.0,
        )
    end

    orders = [
        Order(oid!(acc), long_call, dt + Day(3), 5.0, 1.0),
        Order(oid!(acc), short_call, dt + Day(3), 2.0, -1.0),
    ]
    alloc = @allocated Fastback._fill_option_strategy!(
        acc,
        orders,
        dt + Day(3),
        fill_prices,
        bids,
        asks,
        lasts,
        nothing,
        nothing,
        TradeReason.Normal,
        100.0,
    )
    # Public API returns a fresh stable result vector; internal strategy buffers
    # still reuse account-owned scratch storage.
    @test alloc <= 256

    trades = Fastback._fill_option_strategy!(
        acc,
        [
            Order(oid!(acc), long_call, dt + Day(4), 5.0, 1.0),
            Order(oid!(acc), short_call, dt + Day(4), 2.0, -1.0),
        ],
        dt + Day(4),
        fill_prices,
        bids,
        asks,
        lasts,
        nothing,
        nothing,
        TradeReason.Normal,
        100.0,
    )
    @test isempty(trades)
    @test eltype(trades) === Trade{DateTime}
end

@testitem "FX exposure churn reuses active dependency storage" begin
    using Test, Fastback, Dates

    function drive!(acc, updates)
        inst = acc.positions[1].inst
        for i in 1:64
            dt = acc.last_event_dt + Millisecond(1)
            qty = isodd(i) ? 1.0 : -1.0
            fill_order!(acc, Order(oid!(acc), inst, dt, 100.0, qty);
                dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
            process_step!(acc, dt; fx_updates=updates)
        end
        nothing
    end
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD), track_trades=false, track_cashflows=false)
    deposit!(acc, :USD, 1e6)
    register_cash_asset!(acc, CashSpec(:EUR))
    update_rate!(acc, :EUR, :USD, 1.2)
    for i in 1:1024
        register_instrument!(acc, spot_instrument(Symbol("CHURN", i), :C, :EUR;
            settle_symbol=:USD, margin_symbol=:USD))
    end
    process_step!(acc, DateTime(2026, 1, 1))
    updates = [FXUpdate(cash_asset(acc, :EUR), acc.base_currency, 1.25)]
    drive!(acc, updates)
    drive!(acc, updates)
    @test @allocated(drive!(acc, updates)) == 0
    @test Fastback.check_invariants(acc)
end

@testitem "rebalance allocation stays bounded as the inactive registry grows" begin
    using Test, Fastback, Dates

    function drive!(portfolio, a, b)
        for i in 1:64
            target = isodd(i) ? a : b
            rebalance!(portfolio, DateTime(2026, 1, 1), target)
        end
        nothing
    end
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD), track_trades=false, track_cashflows=false)
    deposit!(acc, :USD, 1e6)
    inst = register_instrument!(acc, spot_instrument(:TRADED, :T, :USD))
    update_marks!(acc, inst, DateTime(2026, 1, 1), 100.0, 100.0, 100.0)
    portfolio = Portfolio(acc)
    a, b = TargetWeights(inst => 0.001), TargetWeights(inst => 0.002)
    @inferred rebalance!(portfolio, DateTime(2026, 1, 1), a)
    drive!(portfolio, a, b)
    drive!(portfolio, a, b)
    small = @allocated drive!(portfolio, a, b)
    for i in 1:4096
        register_instrument!(acc, spot_instrument(Symbol("UNTRADED", i), :U, :USD))
    end
    drive!(portfolio, a, b)
    large = @allocated drive!(portfolio, a, b)
    @test small == large
    # Results own their vectors; scratch storage and non-recorded fills do not
    # add allocations proportional to the registry or retained history.
    @test large <= 64 * 256
    @test Fastback.check_invariants(acc)
end
