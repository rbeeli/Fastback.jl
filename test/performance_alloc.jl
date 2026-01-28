using Dates
using TestItemRunner

@testitem "update_marks! allocates ~0 after warmup" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)
    inst = register_instrument!(acc, Instrument(Symbol("PERF/USD"), :PERF, :USD; margin_mode=MarginMode.PercentNotional))
    pos = get_position(acc, inst)

    dt0 = DateTime(2026, 1, 1)
    dt1 = dt0 + Day(1)
    update_marks!(acc, pos, dt0, 100.0) # warm compile + ensure exposure state

    # warm twice to eliminate first-call cache touch
    update_marks!(acc, pos, dt1, 101.0)
    alloc = @allocated update_marks!(acc, pos, dt1, 101.0)
    @test alloc == 0
end

@testitem "fill_order! allocations are bounded after warmup" begin
    using Test, Fastback, Dates

    function setup_account()
        acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
        deposit!(acc, Cash(:USD), 10_000.0)
        inst = register_instrument!(acc, Instrument(Symbol("PERFFILL/USD"), :PERFFILL, :USD; margin_mode=MarginMode.PercentNotional))
        dt0 = DateTime(2026, 1, 1)
        update_marks!(acc, get_position(acc, inst); dt=dt0, close_price=100.0)
        fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0)
        fill_order!(acc, Order(oid!(acc), inst, dt0 + Day(1), 101.0, 0.5); dt=dt0 + Day(1), fill_price=101.0)
        sizehint!(acc.trades, length(acc.trades) + 2)
        return acc, inst, dt0
    end

    acc_kw, inst_kw, dt0_kw = setup_account()

    trade_alloc = let
        o = Order(0, inst_kw, dt0_kw, 0.0, 0.0)
        Trade(o, 0, dt0_kw, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, TradeReason.Normal)
        @allocated Trade(o, 1, dt0_kw, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, TradeReason.Normal)
    end

    order_kw = Order(oid!(acc_kw), inst_kw, dt0_kw + Day(2), 101.0, -0.25)

    kw_alloc = @allocated fill_order!(acc_kw, order_kw; dt=dt0_kw + Day(2), fill_price=101.0)

    # Julia 1.12 breakdowns (deterministic after warmup):
    # - trade_alloc (112 bytes): Trade heap object incl. GC header
    # - kw path: trade_alloc + 80 bytes (kw wrapper + push! bookkeeping)
    @test trade_alloc == 112
    @test kw_alloc == 192
end

@testitem "process_step! reuses buffers (no allocations) after warmup" begin
    using Test, Fastback, Dates

    alloc = let
        acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
        deposit!(acc, Cash(:USD), 10_000.0)
        inst = register_instrument!(acc, Instrument(Symbol("PERFSTEP/USD"), :PERFSTEP, :USD; margin_mode=MarginMode.PercentNotional))
        pos = get_position(acc, inst)

        dt0 = DateTime(2026, 1, 1)
        dt1 = dt0 + Day(1)
        update_marks!(acc, pos; dt=dt0, close_price=100.0)
        fill_order!(acc, Order(oid!(acc), inst, dt0, 100.0, 1.0); dt=dt0, fill_price=100.0)
        update_marks!(acc, pos; dt=dt1, close_price=101.0)

        marks = [MarkUpdate(inst.index, 102.0, 102.0)]
        # double warmup avoids the single tiny allocation seen on the first post-setup call
        process_step!(acc, dt1; marks=marks, accrue_interest=false, accrue_borrow_fees=false, expiries=false, liquidate=false)
        process_step!(acc, dt1; marks=marks, accrue_interest=false, accrue_borrow_fees=false, expiries=false, liquidate=false)
        @allocated process_step!(acc, dt1; marks=marks, accrue_interest=false, accrue_borrow_fees=false, expiries=false, liquidate=false)
    end
    @test alloc == 0  # deterministic zero after warmup
end
