# # NanoDate Trading Example
#
# This example demonstrates how to use NanoDates with Fastback for nanosecond-precision backtesting.

using Fastback
using Dates
using NanoDates
using Random

# set RNG seed for reproducibility
Random.seed!(42);

# generate synthetic price series with NanoDates timestamps
N = 1_000;
prices = 1000.0 .+ cumsum(randn(N) .+ 0.1);
# Create NanoDate timestamps with nanosecond precision
dts = map(x -> NanoDate(2020, 1, 1) + Nanosecond(x * 1_000_000_000), 0:N-1);

# create trading account with $10'000 start capital
acc = Account();
add_cash!(acc, Cash(:USD), 10_000.0);

# register a dummy instrument
DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))

# data collectors with NanoDate support - note the time_type parameter
collect_equity, equity_data = periodic_collector(Float64, Second(10); time_type=NanoDate);
collect_drawdown, drawdown_data = drawdown_collector(DrawdownMode.Percentage, Second(10); time_type=NanoDate);

println("Starting NanoDate backtesting with ", N, " data points")
println("First timestamp: ", dts[1])
println("Last timestamp: ", dts[end])
println("Timestamp precision: nanoseconds")

# loop over price series
trades_executed = 0
for (dt, price) in zip(dts, prices)
    # randomly trade with 2% probability
    if rand() < 0.02
        quantity = rand() > 0.5 ? 1.0 : -1.0
        order = Order(oid!(acc), DUMMY, dt, price, quantity)
        fill_order!(acc, order, dt, price; fill_qty=0.5order.quantity, commission_pct=0.001)
        trades_executed += 1
    end

    # update position and account P&L
    update_pnl!(acc, DUMMY, price, price)

    # collect data for analysis
    if should_collect(equity_data, dt)
        equity_value = equity(acc, :USD)
        collect_equity(dt, equity_value)
        collect_drawdown(dt, equity_value)
    end
end

# print results
println("\nBacktesting completed successfully!")
println("Trades executed: ", trades_executed)
println("Equity data points collected: ", length(dates(equity_data)))
println("Drawdown data points collected: ", length(dates(drawdown_data)))

# print account summary
show(acc)

# Demonstrate nanosecond precision
println("\n\nNanosecond precision demonstration:")
if !isempty(dates(equity_data))
    println("First equity timestamp: ", dates(equity_data)[1])
    println("Timestamp type: ", typeof(dates(equity_data)[1]))
end