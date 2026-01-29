using Dates
using BenchmarkTools
using Fastback
using InteractiveUtils

function run_backtest()
    # create trading account
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 100_000.0)

    # define instrument
    DUMMY = Instrument(Symbol("DUMMY"), :DUMMY, :USD; margin_mode=MarginMode.PercentNotional)
    register_instrument!(acc, DUMMY)

    dt = DateTime(2018, 1, 2, 9, 30, 0)
    for i = 1:1_000_000
        price = 100.0 + i / 1000
        update_marks!(acc, DUMMY, dt, price, price, price)

        order = Order(oid!(acc), DUMMY, dt, price, 1.0)
        fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price)

        order = Order(oid!(acc), DUMMY, dt, price, -1.0)
        fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price)
    end
end

# 111 ms (Memory estimate: 293.57 MiB, allocs estimate: 4000015.)
@benchmark run_backtest() evals=2 samples=20

using ProfileView
ProfileView.@profview map(i -> run_backtest(), 1:10)


# create trading account
const acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
deposit!(acc, Cash(:USD), 100_000.0)

# define instrument
const DUMMY = Instrument(Symbol("DUMMY"), :DUMMY, :USD; margin_mode=MarginMode.PercentNotional)
register_instrument!(acc, DUMMY)

# get position for instrument
const pos = get_position(acc, DUMMY)

const dt = DateTime(2018, 1, 2, 9, 30, 0)
const price = 100.0

@benchmark update_marks!(acc, pos, dt, price, price, price)

@code_warntype update_marks!(acc, pos, dt, price, price, price)
@code_llvm update_marks!(acc, pos, dt, price, price, price)
@code_native update_marks!(acc, pos, dt, price, price, price)

const order = Order(oid!(acc), DUMMY, dt, price, 1.0)
@code_warntype fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price, fill_qty=0.0, commission=0.0, commission_pct=0.0)
@code_llvm fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price, fill_qty=0.0, commission=0.0, commission_pct=0.0)
@code_native fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price, fill_qty=0.0, commission=0.0, commission_pct=0.0)

@benchmark fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price, fill_qty=0.0, commission=0.0, commission_pct=0.0)
