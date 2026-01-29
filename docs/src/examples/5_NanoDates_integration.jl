# # NanoDates integration example
#
# This example shows how to pair Fastback's timestamp parametrization with
# high-resolution `NanoDate` values from NanoDates.jl. It is derived from
# the random trading walkthrough but focuses on exercising the integration, so
# plotting has been omitted.

using Fastback
using Dates
using NanoDates
using Random

## set RNG seed for reproducibility
Random.seed!(42);

## generate synthetic price series
N = 2_000
prices = 1000.0 .+ cumsum(randn(N) .+ 0.1)
start_dt = NanoDate(2020, 1, 1)
dts = [start_dt + Hour(i) for i in 0:N-1]

## create trading account with $10'000 start capital and NanoDate support (margin-enabled for shorting)
acc = Account(; time_type=NanoDate, mode=AccountMode.Margin, base_currency=:USD)
deposit!(acc, Cash(:USD), 10_000.0)

## register a dummy instrument
DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD; time_type=NanoDate, margin_mode=MarginMode.PercentNotional))

## data collector for account equity and drawdowns (sampling every hour)
collect_equity, equity_data = periodic_collector(Float64, Hour(1); time_type=NanoDate)
collect_drawdown, drawdown_data = drawdown_collector(DrawdownMode.Percentage, Hour(1); time_type=NanoDate)

## loop over price series
for (dt, price) in zip(dts, prices)
    ## randomly trade with 1% probability
    if rand() < 0.01
        quantity = rand() > 0.4 ? 1.0 : -1.0
        order = Order(oid!(acc), DUMMY, dt, price, quantity)
        fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price, fill_qty=0.75order.quantity, commission_pct=0.001)
    end

    ## update position and account P&L
    update_marks!(acc, DUMMY, dt, price, price, price)

    ## collect data for analysis
    if should_collect(equity_data, dt)
        equity_value = equity(acc, :USD)
        collect_equity(dt, equity_value)
        collect_drawdown(dt, equity_value)
    end
end

## print account summary
show(acc)
