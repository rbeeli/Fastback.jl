# # Tables.jl integration example
# 
# This example demonstrates the Tables.jl integration in Fastback by running
# a simple backtest and then converting account data to DataFrames for display.
# 
# The Tables.jl interface provides zero-copy views of trades, positions, 
# cash balances, equity balances, and collector output, making it easy to 
# export results to DataFrames.jl, CSV.jl, Arrow.jl or any other package 
# that consumes Tables-compatible sources.

using Fastback
using DataFrames
using Dates
using Random

## set RNG seed for reproducibility
Random.seed!(123);

## generate synthetic price series
N = 500;
prices = 100.0 .+ cumsum(randn(N) .* 0.5 .+ 0.05);
dts = map(x -> DateTime(2021, 1, 1) + Hour(x), 0:N-1);

## create trading account with $5'000 start capital and custom metadata types
const OrderMeta = NamedTuple{(:signal,),Tuple{String}}
const InstMeta = NamedTuple{(:sector,),Tuple{Symbol}}

acc = Account(; odata=OrderMeta, idata=InstMeta);
deposit!(acc, Cash(:USD), 5_000.0);

## register instruments with metadata
AAPL = register_instrument!(acc, Instrument(Symbol("AAPL/USD"), :AAPL, :USD; metadata=(sector=:tech,)));
MSFT = register_instrument!(acc, Instrument(Symbol("MSFT/USD"), :MSFT, :USD; metadata=(sector=:tech,)));

## data collectors
collect_equity, equity_data = periodic_collector(Float64, Hour(12));
collect_drawdown, drawdown_data = drawdown_collector(DrawdownMode.Percentage, Hour(12));

## simple momentum strategy
prev_price = prices[1];
for (i, (dt, price)) in enumerate(zip(dts, prices))
    global prev_price

    ## trade every 10 hours based on price momentum
    if i % 10 == 0 && i > 10
        momentum = (price - prev_price) / prev_price

        if momentum > 0.02  # buy signal
            quantity = 10.0
            order = Order(oid!(acc), AAPL, dt, price, quantity; metadata=(signal="mom",))
            fill_order!(acc, order, dt, price; commission_pct=0.001)

        elseif momentum < -0.02  # sell signal
            quantity = -8.0
            order = Order(oid!(acc), MSFT, dt, price, quantity; metadata=(signal="mom",))
            fill_order!(acc, order, dt, price; commission_pct=0.001)
        end

        prev_price = price
    end

    ## update positions P&L
    update_pnl!(acc, AAPL, price, price)
    update_pnl!(acc, MSFT, price, price)

    ## collect equity data
    if should_collect(equity_data, dt)
        equity_value = equity(acc, :USD)
        collect_equity(dt, equity_value)
        collect_drawdown(dt, equity_value)
    end
end

## print account summary
show(acc)

#---------------------------------------------------------

# ### Convert trades to DataFrame

df_trades = DataFrame(trades_table(acc))

println(df_trades)

#---------------------------------------------------------

# ### Convert positions to DataFrame

df_positions = DataFrame(positions_table(acc))

println(df_positions)

#---------------------------------------------------------

# ### Convert cash balances to DataFrame

df_balances = DataFrame(balances_table(acc))

println(df_balances)

#---------------------------------------------------------

# ### Convert equity balances to DataFrame

df_equities = DataFrame(equities_table(acc))

println(df_equities)

#---------------------------------------------------------

# ### Convert equity collector data to DataFrame

df_equity_history = DataFrame(equity_data)

println(df_equity_history)

#---------------------------------------------------------

# ### Convert balance collector data to DataFrame

df_drawdown_history = DataFrame(drawdown_data)

println(df_drawdown_history)
