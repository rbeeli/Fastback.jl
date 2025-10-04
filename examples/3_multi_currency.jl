# # Multi-currency trading example
#
# This example demonstrates how to trade assets quoted in different currencies.
# The account has balances in USD, EUR and GBP, and trades stocks denoted
# in those currencies.
# The total equity is calculated in USD.
# A spot exchange rate helper is used to convert between different currencies.

using Fastback
using Dates
using Random
using DataFrames

## set RNG seed for reproducibility
Random.seed!(42);

## generate synthetic price series for Tesla (USD), Porsche (EUR) and Tesco (GBP)
N = 2_000;
df = DataFrame([
    :date => map(x -> DateTime(2020, 1, 1) + Hour(x), 0:N-1),
    :TSLA => 170 .+ cumsum(randn(N) .+ 0.12),
    :POAHY => 4.5 .+ cumsum(randn(N) .+ 0.02),
    :TSCO_L => 307 .+ cumsum(randn(N) .+ 0.08)
]);

## create cash objects for USD, EUR and GBP
USD = Cash(:USD; digits=2);
EUR = Cash(:EUR; digits=2);
GBP = Cash(:GBP; digits=2);

## create trading account with 10'000 USD, 5'000 EUR and 20'000 GBP cash
acc = Account();
deposit!(acc, USD, 10_000);
deposit!(acc, EUR, 5_000);
deposit!(acc, GBP, 20_000);

## exchange rates for spot rates
er = SpotExchangeRates();

## set spot exchange rates once
add_asset!(er, USD);
add_asset!(er, EUR);
add_asset!(er, GBP);
update_rate!(er, EUR, USD, 1.07);
update_rate!(er, GBP, USD, 1.27);

show(er)

## register stock instruments 
instruments = [
    register_instrument!(acc, Instrument(:TSLA, :TSLA, :USD)), # Tesla (USD denominated)
    register_instrument!(acc, Instrument(:POAHY, :POAHY, :EUR)), # Porsche (EUR denominated)
    register_instrument!(acc, Instrument(:TSCO_L, :TSCO_L, :GBP)), # Tesco (GBP denominated)
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
        quantity = rand() > 0.5 ? 10.0 : -10.0
        order = Order(oid!(acc), inst, dt, price, quantity)
        fill_order!(acc, order, dt, price; commission_pct=0.001)
    end

    ## update position and account P&L
    for inst in instruments
        price = df[i, inst.symbol]
        update_pnl!(acc, inst, price, price)
    end

    ## collect data for plotting
    if should_collect(equity_data, dt)
        total_equity = (
            equity(acc, :USD) +
            equity(acc, :EUR) * get_rate(er, EUR, USD) +
            equity(acc, :GBP) * get_rate(er, GBP, USD)
        )
        collect_equity(dt, total_equity)
        collect_drawdown(dt, total_equity)
    end
end

## print account summary
show(acc)

#---------------------------------------------------------

# ### Plot account equity curve

using Plots, Printf
theme(:juno; titlelocation=:left, titlefontsize=10, widen=false, fg_legend=:false)

## plot equity curve
p = plot(dates(equity_data), values(equity_data);
    title="Account",
    label="Equity",
    linetype=:steppost,
    yformatter=:plain,
    size=(800, 400),
    color="#BBBB00");
p

#---------------------------------------------------------

# ### Plot account equity drawdown curve

## plot drawdown curve
p = plot(dates(drawdown_data), 100values(drawdown_data);
    title="Equity drawdowns [%]",
    legend=false,
    linetype=:steppost,
    color="#BB0000",
    yformatter=y -> @sprintf("%.1f%%", y),
    size=(800, 200),
    fill=(0, "#BB000033"));
p
