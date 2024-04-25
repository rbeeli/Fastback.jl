# Portfolio trading strategy example
# -------------------------------
# This example demonstrates how to run a backtest with multiple assets, i.e.
# trading a portfolio of assets.
#
# The price data is loaded from a CSV file containing daily close prices for
# the stocks AAPL, NVDA, TSLA, and GE, ranging from 2022-01-03 to 2024-04-22.
# 
# The strategy buys one stock if the last 5 days were positive,
# and sells it again if the last 2 days were negative.
# Each trade is executed at a fee of 0.1%.
# 
# When missing data points are detected for a stock,
# all open positions for that stock are closed.
# Logic of this type is common in real-world strategies
# and harder to implement in a vectorized way,
# showcasing the flexibility of Fastback.
#
# The account equity, balance and drawdowns are collected for
# every day and plotted at the end using the Plots package.
# Additionally, the performance and P&L breakdown of each stock is plotted.

using Fastback
using Dates
using CSV
using DataFrames

# load CSV daily stock data for tickers AAPL, NVDA, TSLA, GE
df_csv = DataFrame(CSV.File("examples/data/stocks_1d.csv"; dateformat="yyyy-mm-dd HH:MM:SS"));

# ticker strings to symbols
df_csv.ticker = Symbol.(df_csv.ticker);

# transform long to wide format (pivot)
df = unstack(df_csv, :dt_close, :ticker, :close)
# df = coalesce.(df, NaN) # replace missing values with NaN
describe(df)

symbols = Symbol.(names(df)[2:end]);

# define instrument objects for all tickers
instruments = map(t -> Instrument(t[1], t[2]), enumerate(symbols))

# create trading account
acc = Account{Nothing}(instruments, 100_000.0);

# data collector for account balance, equity and drawdowns (sampling every day)
collect_balance, balance_data = periodic_collector(Float64, Day(1));
collect_equity, equity_data = periodic_collector(Float64, Day(1));
collect_drawdown, drawdown_data = drawdown_collector(DrawdownMode.Percentage, Day(1));

function open_position!(acc, inst, dt, price)
    # invest 20% of equity in the position
    qty = 0.2equity(acc) / price
    order = Order(oid!(acc), inst, dt, price, qty)
    fill_order!(acc, order, dt, price; fee_pct=0.001)
end

function close_position!(acc, inst, dt, price)
    # close position for instrument if any
    pos = get_position(acc, inst)
    has_exposure(pos) || return
    order = Order(oid!(acc), inst, dt, price, -quantity(pos))
    fill_order!(acc, order, dt, price; fee_pct=0.001)
end

# loop over each row of DataFrame
for i in 6:nrow(df)
    row = df[i, :]
    dt = row.dt_close

    # loop over all instruments and check strategy rules
    for inst in instruments
        symbol = inst.symbol
        price = row[symbol]

        window_open = @view df[i-5:i, symbol]
        window_close = @view df[i-2:i, symbol]

        # close position of instrument if missing data
        if any(ismissing.(window_open))
            close_position!(acc, inst, dt, avg_price(get_position(acc, inst)))
            continue
        end

        if !is_exposed_to(acc, inst)
            # buy if last 5 days were positive
            all(diff(window_open) .> 0) && open_position!(acc, inst, dt, price)
        else
            # close position if last 2 days were negative
            all(diff(window_close) .< 0) && close_position!(acc, inst, dt, price)
        end

        # update position and account P&L
        update_pnl!(acc, inst, price)
    end

    # close all positions at the end of backtest
    if i == nrow(df)
        for inst in instruments
            price = row[inst.symbol]
            close_position!(acc, inst, dt, price)
        end
    end

    # collect data for plotting
    collect_balance(dt, balance(acc))
    collect_equity(dt, equity(acc))
    collect_drawdown(dt, equity(acc))
end

# print account statistics
show(acc)

# plots
using Plots, Query, Printf, Measures

theme(:juno;
    titlelocation=:left,
    titlefontsize=10,
    widen=false,
    fg_legend=:false)

# cash_ratio = values(equity_data) ./ (values(balance_data) .+ values(equity_data))

# equity / balance
p1 = plot(
    dates(balance_data), values(balance_data);
    title="Account",
    label="Balance",
    linetype=:steppost,
    yformatter=:plain,
    color="#0088DD");
plot!(p1,
    dates(equity_data), values(equity_data);
    label="Equity",
    linetype=:steppost,
    color="#BBBB00");

# drawdowns
p2 = plot(
    dates(drawdown_data), 100values(drawdown_data);
    title="Drawdowns [%]",
    legend=false,
    color="#BB0000",
    yformatter=y -> @sprintf("%.1f%%", y),
    linetype=:steppost,
    fill=(0, "#BB000033"));

# stocks performance
p3 = plot(
    df.dt_close, df[!, 2] ./ df[1, 2];
    title="Stocks performance (normalized)",
    yformatter=y -> @sprintf("%.1f", y),
    label=names(df)[2],
    linetype=:steppost,
    color=:green);
for i in 3:ncol(df)
    plot!(p3,
        df.dt_close, df[!, i] ./ df[1, i];
        label=names(df)[i])
end

# P&L breakdown
pnl_by_inst = trades(acc) |>
              @groupby(symbol(_)) |>
              @map({
                  symbol = key(_),
                  pnl = sum(map(x -> realized_pnl(x), _))
              }) |> DataFrame;
p4 = bar(string.(pnl_by_inst.symbol), pnl_by_inst.pnl;
    legend=false,
    title="P&L breakdown",
    permute=(:x, :y),
    xlims=(0, size(pnl_by_inst)[1]),
    yformatter=y -> format_ccy(acc, y),
    color="#BBBB00",
    linecolor=nothing,
    bar_width=0.5)

plot(p1, p2, p3, p4;
    layout=@layout[a{0.4h}; b{0.15h}; c{0.3h}; d{0.15h}],
    size=(600, 900), margin=0mm, left_margin=5mm)
