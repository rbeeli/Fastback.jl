# # Timestamps64 integration example
#
# This example shows how to pair Fastback's timestamp parametrization with
# high-resolution `Timestamp64` values from Timestamps64.jl.
#
# Timestamps64.jl provides nanosecond-resolution timestamps based on `Int64` values,
# which makes them very efficient in terms of memory and performance.
# They are particularly useful for high-frequency trading applications.
# Compared to NanoDates.jl, Timestamps64.jl has a smaller memory footprint
# (8 bytes vs. 16 bytes), and is faster for arithmetic operations.
#
# This example is derived from the random trading walkthrough but focuses on
# exercising the integration, so plotting has been omitted.

using Fastback
using Dates
using Timestamps64
using Random

## set RNG seed for reproducibility
Random.seed!(42);

## generate synthetic price series
N = 2_000
prices = 1000.0 .+ cumsum(randn(N) .+ 0.1)
start_dt = Timestamp64(2020, 1, 1)
dts = [start_dt + Hour(i) for i in 0:N-1]

## create trading account with $10'000 start capital and Timestamp64 support
acc = Account(; time_type=Timestamp64)
deposit!(acc, Cash(:USD), 10_000.0)

## register a dummy instrument
DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))

## data collector for account equity and drawdowns (sampling every hour)
collect_equity, equity_data = periodic_collector(Float64, Hour(1); time_type=Timestamp64)
collect_drawdown, drawdown_data = drawdown_collector(DrawdownMode.Percentage, Hour(1); time_type=Timestamp64)

## loop over price series
for (dt, price) in zip(dts, prices)
    ## randomly trade with 1% probability
    if rand() < 0.01
        quantity = rand() > 0.4 ? 1.0 : -1.0
        order = Order(oid!(acc), DUMMY, dt, price, quantity)
        fill_order!(acc, order, dt, price; fill_qty=0.75order.quantity, commission_pct=0.001)
    end

    ## update position and account P&L
    update_pnl!(acc, DUMMY, price, price)

    ## collect data for analysis
    if should_collect(equity_data, dt)
        equity_value = equity(acc, :USD)
        collect_equity(dt, equity_value)
        collect_drawdown(dt, equity_value)
    end
end

## print account summary
show(acc)
