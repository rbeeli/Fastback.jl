# # Multi-currency trading example
# 
# TODO

using Fastback
using Dates
using Random
using DataFrames

## set RNG seed for reproducibility
Random.seed!(42);

## generate synthetic price series
N = 2_000;
df = DataFrame([
    :date => map(x -> DateTime(2020, 1, 1) + Hour(x), 0:N-1),
    :BTC => 65_000 .+ cumsum(randn(N) .+ 0.1),
    :ETH => 4_000 .+ cumsum(randn(N) .+ 0.1)
]);

## create a USD denominated trading account that uses spot exchange rates
acc = Account{Nothing,Nothing}(Asset(:USD); exchange_rates=SpotExchangeRates{Nothing}());

## add 10 BTC and 100 ETH start capital funds
add_funds!(acc, Asset(:BTC; digits=5), 10);
add_funds!(acc, Asset(:ETH; digits=5), 100);

## set exchange rates for BTC and ETH once
add_asset!.(Ref(acc.exchange_rates), acc.assets);
update_rate!(acc.exchange_rates, get_asset(acc, :BTC), get_asset(acc, :USD), 65_000);
update_rate!(acc.exchange_rates, get_asset(acc, :ETH), get_asset(acc, :USD), 4_000);

show(acc.exchange_rates)

## register crypto instruments
instruments = [
    register_instrument!(acc, Instrument(Symbol("BTC"), :BTC, :USD)),
    register_instrument!(acc, Instrument(Symbol("ETH"), :ETH, :USD))
];

## data collector for account equity and drawdowns (sampling every hour)
collect_equity, equity_data = periodic_collector(Float64, Hour(1));
collect_drawdown, drawdown_data = drawdown_collector(DrawdownMode.Percentage, Hour(1));

## loop over price series
for i in 1:N
    dt = df.date[i]

    ## randomly trade with 1% probability
    if rand() < 0.01
        inst = rand(instruments)
        price = df[i, inst.symbol]
        quantity = rand() > 0.4 ? 0.1 : -0.1 # BTC or ETH
        order = Order(oid!(acc), inst, dt, price, quantity)
        fill_order!(acc, order, dt, price; fee_pct=0.001)
    end

    ## update position and account P&L
    for inst in instruments
        price = df[i, inst.symbol]
        update_pnl!(acc, inst, price)
    end

    ## collect data for plotting
    if should_collect(equity_data, dt)
        equity = total_equity(acc)
        collect_equity(dt, equity)
        collect_drawdown(dt, equity)
    end
end

show(acc)