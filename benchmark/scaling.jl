include("benchmarks.jl")

function changing_fx!(acc, updates)
    for i in 1:BLOCK_SIZE
        u = updates[1]
        updates[1] = FXUpdate(u.from_cash, u.to_cash, isodd(i) ? 1.1 : 1.2)
        process_step!(acc, acc.last_event_dt + Millisecond(1); fx_updates=updates,
            accrue_interest=false, accrue_borrow_fees=false, expiries=false)
    end
end

function no_rebalance!(p, target)
    dt = p.account.last_event_dt
    for _ in 1:BLOCK_SIZE
        dt += Millisecond(1)
        rebalance!(p, dt, target)
    end
    nothing
end

function churn!(acc)
    dt = acc.last_event_dt
    inst = acc.positions[1].inst
    for i in 1:BLOCK_SIZE
        dt += Millisecond(1)
        order = Order(oid!(acc), inst, dt, 100.0, isodd(i) ? -1.0 : 1.0)
        fill_order!(acc, order; dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    end
end

function one_option_mark!(acc, marks, changing)
    for i in 1:BLOCK_SIZE
        px = changing && isodd(i) ? 101.0 : 100.0
        marks[1] = MarkUpdate(1, px, px, px)
        process_step!(acc, acc.last_event_dt + Millisecond(1); marks=marks,
            accrue_interest=false, accrue_borrow_fees=false, expiries=false)
    end
end

function expire!(acc)
    process_step!(acc, START + Year(1))
end

function main_scaling()
    println("Julia ", VERSION, "; CPU=", Sys.CPU_NAME, "; threads=", Threads.nthreads())
    for n in (1, 100, 1000, 10000)
        acc = fixture(n; cross=true)
        updates = [FXUpdate(cash_asset(acc, :EUR), acc.base_currency, 1.1)]
        report("sparse changing FX N=$n open=1", @benchmark changing_fx!($acc, $updates) samples=30 evals=1 seconds=0.3)
        Fastback.check_invariants(acc)
    end
    for n in (1, 100, 1000, 10000)
        acc = fixture(n)
        p = Portfolio(acc)
        target = TargetWeights(1 => 1e-10)
        tc = acc.trade_count
        report("no-op rebalance N=$n target=1", @benchmark no_rebalance!($p, $target) samples=30 evals=1 seconds=0.3)
        @assert acc.trade_count == tc
        Fastback.check_invariants(acc)
    end
    for n in (1, 100, 1000, 10000)
        acc = fixture(n; kind=:future, open_all=true)
        report("future open/close first N=$n", @benchmark churn!($acc) samples=30 evals=1 seconds=0.3)
        Fastback.check_invariants(acc)
        trial = @benchmark expire!(acc) setup=(acc=deepcopy($acc)) samples=10 evals=1 seconds=0.3
        report("all futures expire N=$n", trial; operations=1)
        c = deepcopy(acc)
        expire!(c)
        Fastback.check_invariants(c)
    end
    for n in (1, 32, 128, 512), mixed in (false, true)
        mixed && n == 1 && continue
        acc = fixture(n; kind=:option, open_all=true)
        if mixed
            update_option_underlying_price!(acc, first(acc.positions).inst, 100.0)
            for i in 2:2:n
                inst = acc.positions[i].inst
                fill_order!(acc, Order(oid!(acc), inst, START, 90.0, -2.0);
                    dt=START, fill_price=90.0, bid=90.0, ask=90.0, last=90.0)
            end
        end
        marks = [MarkUpdate(1, 100.0, 100.0, 100.0)]
        for changing in (false, true)
            report("option mark N=$n mixed=$mixed change=$changing",
                @benchmark one_option_mark!($acc, $marks, $changing) samples=30 evals=1 seconds=0.3)
        end
        if mixed
            report("mixed option fill N=$n",
                @benchmark fills!($acc) samples=30 evals=1 seconds=0.3)
        end
        Fastback.check_invariants(acc)
    end
end

main_scaling()
