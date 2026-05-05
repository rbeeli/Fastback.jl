using Dates
using TestItemRunner

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
