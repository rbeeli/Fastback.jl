# Random trading strategy example
# -------------------------------
# This dummy example demonstrates how to backtest a simple random trading strategy
# using Fastback that randomly buys or sells an instrument with a probability of 1%.
# The strategy is applied to synthetic data generated in the script where
# the price of the instrument is a random walk with a drift of 0.1 and
# the initial price is 1000.0. Buy and sell orders use the same price series.

using Fastback
using Dates

# synthetic data
N = 1_000;
prices = 1000.0 .+ cumsum(randn(N) .+ 0.1);
dts = map(x -> DateTime(2020, 1, 1) + Hour(x), 0:N);

# create instrument
inst_dummy = Instrument(1, "DUMMY");
instruments = [inst_dummy];

# create trading account
acc = Account(instruments, 100_000.0);

# plot data collectors
collect_balance, balance_curve = periodic_collector(Float64, Second(1));
collect_equity, equity_curve = periodic_collector(Float64, Second(1));
collect_open_orders, open_orders_curve = max_value_collector(Int64);
collect_drawdown, drawdown_curve = drawdown_collector(DrawdownMode.Percentage, (v, dt, equity) -> dt - v.last_dt >= Second(1));

pos = get_position(acc, inst_dummy);

# backtest random trading strategy
for i in 1:N
    dt = dts[i]
    price = prices[i]

    if i < N
        # randomly trade with 1% probability
        if rand() < 0.01
            quantity = rand() > 0.5 ? 1.0 : -1.0
            order = Order(inst_dummy, quantity, dt)
            execute_order!(acc, order, dt, price)
        end
    else
        # close all open positions at end of backtest
        if pos.quantity !== 0.0
            order = Order(inst_dummy, -pos.quantity, dt)
            execute_order!(acc, order, dt, price)
        end
    end

    # update position and account PnL
    update_pnl!(acc, pos, price)

    # collect data for analysis
    collect_balance(dt, acc.balance)
    collect_equity(dt, acc.equity)
    collect_open_orders(dt, length(acc.positions))
    collect_drawdown(dt, acc.equity)
end

# print account statistics
show(acc)
