using Dates
using BenchmarkTools
using Fastback
using InteractiveUtils

function run_backtest()
    # define instrument
    DUMMY = Instrument(1, "DUMMY")
    instruments = [DUMMY]

    # create trading account
    acc = Account{Nothing}(instruments, 100_000.0)

    # get position for instrument
    pos = get_position(acc, DUMMY)

    dt = DateTime(2018, 1, 2, 9, 30, 0)
    for i = 1:1_000_000
        price = 100.0 + i / 1000
        
        update_pnl!(acc, pos, price)

        order = Order(oid!(acc), DUMMY, dt, price, 1.0)
        fill_order!(acc, order, dt, price)

        order = Order(oid!(acc), DUMMY, dt, price, -1.0)
        fill_order!(acc, order, dt, price)
    end
end

# 111 ms (Memory estimate: 293.57 MiB, allocs estimate: 4000015.)
@benchmark run_backtest() evals=2 samples=20

using ProfileView
ProfileView.@profview map(i -> run_backtest(), 1:10)


# define instrument
const DUMMY = Instrument(1, "DUMMY")
const instruments = [DUMMY]

# create trading account
const acc = Account{Nothing}(instruments, 100_000.0)

# get position for instrument
const pos = get_position(acc, DUMMY)

const dt = DateTime(2018, 1, 2, 9, 30, 0)
const price = 100.0

@benchmark update_pnl!(acc, pos, price)

@code_warntype update_pnl!(acc, pos, price)
@code_llvm update_pnl!(acc, pos, price)
@code_native update_pnl!(acc, pos, price)

const order = Order(oid!(acc), DUMMY, dt, price, 1.0)
@code_warntype fill_order!(acc, order, dt, price; fill_quantity=0.0, fees_ccy=0.0, fees_pct=0.0)
@code_llvm fill_order!(acc, order, dt, price; fill_quantity=0.0, fees_ccy=0.0, fees_pct=0.0)
@code_native fill_order!(acc, order, dt, price; fill_quantity=0.0, fees_ccy=0.0, fees_pct=0.0)

@benchmark fill_order!(acc, order, dt, price; fill_quantity=0.0, fees_ccy=0.0, fees_pct=0.0)
