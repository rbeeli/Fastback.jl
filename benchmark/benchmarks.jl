using BenchmarkTools, Dates, Fastback, Printf

const START = DateTime(2026, 1, 1)
const BLOCK_SIZE = 256

function fixture(
    n::Int
    ;
    kind::Symbol=:spot,
    history::Bool=false,
    cross::Bool=false,
    open_all::Bool=false,
    shorts::Bool=false,
)
    broker = shorts ? FlatFeeBroker(; lend_by_cash=Dict(:USD => 0.05)) : NoOpBroker()
    acc = Account(; broker=broker, funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD), track_trades=history, track_cashflows=history)
    deposit!(acc, :USD, 1e12)

    if cross
        register_cash_asset!(acc, CashSpec(:EUR))
        update_rate!(acc, :EUR, :USD, 1.1)
    end

    for i in 1:n
        spec = if kind == :option
            option_instrument(Symbol("OPT", i), :UNDERLYING, :USD;
                strike=100.0 + i, expiry=START + Year(1), right=OptionRight.Call)
        elseif kind == :future
            future_instrument(Symbol("FUT", i), :FUTURE, :USD;
                expiry=START + Year(1), margin_requirement=MarginRequirement.PercentNotional,
                margin_init_long=0.1, margin_init_short=0.1,
                margin_maint_long=0.05, margin_maint_short=0.05)
        else
            spot_instrument(Symbol("SPOT", i), :ASSET, cross ? :EUR : :USD;
                settle_symbol=:USD, margin_symbol=:USD, short_borrow_rate=shorts ? 0.1 : 0.0)
        end
        inst = register_instrument!(acc, spec)
        if i == 1 || open_all
            fill_order!(acc, Order(oid!(acc), inst, START, 100.0, shorts ? -1.0 : 1.0);
                dt=START, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
        end
    end

    Fastback.check_invariants(acc)
    acc
end

function steps!(acc, marks, ::Val{DEFAULT}) where {DEFAULT}
    dt = acc.last_event_dt

    for i in 1:BLOCK_SIZE
        dt += Millisecond(1)
        price = 100.0 + (i % 2)
        marks[1] = MarkUpdate(1, price, price, price)
        process_step!(acc, dt; marks=marks,
            accrue_interest=DEFAULT, accrue_borrow_fees=DEFAULT, expiries=DEFAULT)
    end
    nothing
end

function fills!(acc, n::Int=BLOCK_SIZE)
    empty!(acc.trades)
    empty!(acc.cashflows)
    dt = acc.last_event_dt
    inst = first(acc.positions).inst

    for i in 1:n
        dt += Millisecond(1)
        order = Order(oid!(acc), inst, dt, 100.0, isodd(i) ? 1.0 : -1.0)
        fill_order!(acc, order; dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    end
    nothing
end

function fx_steps!(acc, updates)
    for _ in 1:BLOCK_SIZE
        process_step!(acc, acc.last_event_dt + Millisecond(1); fx_updates=updates,
            accrue_interest=false, accrue_borrow_fees=false, expiries=false)
    end
    nothing
end

function option_marks!(acc, marks, ::Val{BATCH}) where {BATCH}
    dt = acc.last_event_dt + Millisecond(1)
    if BATCH
        process_step!(acc, dt; marks=marks,
            accrue_interest=false, accrue_borrow_fees=false, expiries=false)
    else
        for mark in marks
            update_marks!(acc, acc.positions[mark.inst_index], dt, mark.bid, mark.ask, mark.last)
        end
    end
    nothing
end

function report(label, trial; operations::Int=BLOCK_SIZE)
    result = median(trial)
    @printf("%-42s %11.1f ns/op %9.1f B/op %7.2f allocs/op\n",
        label, result.time / operations, result.memory / operations, result.allocs / operations)
end

function main()
    println("Julia ", VERSION, "; CPU=", Sys.CPU_NAME, "; threads=", Threads.nthreads())

    for n in (1, 100, 1000, 10000)
        acc = fixture(n)
        marks = [MarkUpdate(1, 100.0, 100.0, 100.0)]
        for default in (false, true)
            mode = Val(default)
            report("steps N=$n default=$default",
                @benchmark steps!($acc, $marks, $mode) samples=50 evals=1 seconds=0.5)
        end
        Fastback.check_invariants(acc)
    end

    for n in (1, 1000, 10000)
        acc = fixture(n; shorts=true)
        marks = [MarkUpdate(1, 100.0, 100.0, 100.0)]
        report("financing N=$n eligible_shorts=1",
            @benchmark steps!($acc, $marks, Val(true)) samples=50 evals=1 seconds=0.5)
        Fastback.check_invariants(acc)
    end

    for kind in (:spot, :future), history in (false, true)
        acc = fixture(1; kind=kind, history=history)
        sizehint!(acc.trades, BLOCK_SIZE)
        report("fresh fills $kind history=$history",
            @benchmark fills!($acc) samples=50 evals=1 seconds=0.5)
        Fastback.check_invariants(acc)
    end

    # Retain 100,000 distinct orders/trades per evaluation. Setup and vector
    # reservation are excluded; object allocation and GC remain in the trial.
    history_trial = @benchmark fills!(acc, 100_000) setup=(
        acc=fixture(1; history=true); sizehint!(acc.trades, 100_000)
    ) samples=10 evals=1 seconds=1
    report("retained history 100,000 fills", history_trial; operations=100_000)

    for n in (100, 1000, 10000)
        acc = fixture(n; cross=true, open_all=true)
        chf = register_cash_asset!(acc, CashSpec(:CHF))
        unrelated = [FXUpdate(chf, acc.base_currency, 1.2)]
        related = [FXUpdate(cash_asset(acc, :EUR), acc.base_currency, 1.2)]
        for (label, updates) in (("unrelated", unrelated), ("related", related))
            report("FX N=$n $label",
                @benchmark fx_steps!($acc, $updates) samples=50 evals=1 seconds=0.5)
        end
        Fastback.check_invariants(acc)
    end

    for n in (4, 32, 128, 512)
        acc = fixture(n; kind=:option, open_all=true)
        marks = [MarkUpdate(i, 101.0, 101.0, 101.0) for i in 1:n]
        for batch in (false, true)
            mode = Val(batch)
            report("$n option marks batch=$batch",
                @benchmark option_marks!($acc, $marks, $mode) samples=50 evals=1 seconds=0.5;
                operations=1)
        end
        report("single option fill group=$n",
            @benchmark fills!($acc) samples=50 evals=1 seconds=0.5)
        Fastback.check_invariants(acc)
    end
end

main()
