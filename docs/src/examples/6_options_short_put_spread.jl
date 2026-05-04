# # Systematic short put spread example
#
# This example shows a simple options strategy on synthetic SPY-like data.
# The strategy sells one 30-delta put and buys a lower-strike put as protection,
# holds the vertical spread to cash-settled expiry, and then repeats.
#
# The data is a static CSV pair: daily SPY-like underlying marks and a
# ThetaData-style put option quote table with bid/ask/last/delta rows. The
# important Fastback pieces are:
#
# - listed option instruments with strikes, expiries, rights, and multipliers
# - `OptionUnderlyingUpdate` for one underlying/quote chain mark
# - `MarkUpdate` for bid/ask/last option marks
# - multi-leg fills with option premium cash settlement
# - vertical spread margin relief and cash-settled expiry processing

using Fastback
using Dates
using CSV
using DataFrames
using Statistics

const START_CAPITAL = 100_000.0
const CONTRACTS = 3.0
const TARGET_DELTA = 0.30
const SPREAD_WIDTH = 10.0
const ENTRY_DTE = 30
const ENTRY_GAP = 21

data_dir = joinpath(@__DIR__, "data"); #src
#md data_dir = joinpath(@__DIR__, "..", "data");

## load synthetic SPY and SPY put option data
market = DataFrame(CSV.File(joinpath(data_dir, "options_spy_1d.csv"); dateformat="yyyy-mm-dd"));
sort!(market, :dt);
option_quotes = DataFrame(CSV.File(joinpath(data_dir, "options_spy_put_quotes_1d.csv"); dateformat="yyyy-mm-dd"));
sort!(option_quotes, [:dt, :expiry, :strike]);

quote_by_key = Dict(
    (row.dt, row.expiry, row.strike) => (bid=row.bid, ask=row.ask, last=row.last)
    for row in eachrow(option_quotes)
);

function option_symbol(expiry::Date, right::Char, strike::Real)
    Symbol("SPY_$(Dates.format(expiry, "yyyymmdd"))_$(right)$(Int(round(strike)))")
end

function spy_put(expiry::Date, strike::Real)
    option_instrument(
        option_symbol(expiry, 'P', strike),
        :SPY,
        :USD;
        strike=Float64(strike),
        expiry=expiry,
        right=OptionRight.Put,
        multiplier=100.0,
        time_type=Date,
    )
end

function run_short_put_spread_backtest(market, option_quotes, quote_by_key)
    ## account: margin-enabled, with IBKR Pro Fixed option commissions
    acc = Account(;
        time_type=Date,
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=IBKRProFixedBroker(; time_type=Date),
    )
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, START_CAPITAL)

    ## data collectors
    collect_equity, equity_data = periodic_collector(Float64, Day(1); time_type=Date)
    collect_drawdown, drawdown_data = drawdown_collector(DrawdownMode.Percentage, Day(1); time_type=Date)

    registered_options = Instrument{Date}[]
    open_legs = Instrument{Date}[]
    entries = DataFrame(
        entry_dt=Date[],
        expiry=Date[],
        short_strike=Float64[],
        long_strike=Float64[],
        credit=Float64[],
        margin_used=Float64[],
    )

    next_entry_idx = 1

    for i in eachindex(market.dt)
        dt = market.dt[i]
        spot = market.spot[i]

        ## Mark all live options and update the option chain's underlying price.
        marks = MarkUpdate[]
        for inst in registered_options
            is_expired(inst, dt) && continue
            q = quote_by_key[(dt, inst.spec.expiry, inst.spec.strike)]
            push!(marks, MarkUpdate(inst.index, q.bid, q.ask, q.last))
        end

        process_step!(
            acc,
            dt;
            option_underlyings=[OptionUnderlyingUpdate(:SPY, :USD, spot)],
            marks=marks,
            expiries=true,
        )

        filter!(inst -> get_position(acc, inst).quantity != 0.0, open_legs)

        ## Enter one 30 DTE put credit spread at a time.
        if isempty(open_legs) && i >= next_entry_idx && i + ENTRY_DTE <= nrow(market)
            expiry = market.dt[i + ENTRY_DTE]
            chain = option_quotes[(option_quotes.dt .== dt) .& (option_quotes.expiry .== expiry) .& (option_quotes.right .== "P"), :]
            short_idx = argmin(abs.(abs.(chain.delta) .- TARGET_DELTA))
            short_quote = chain[short_idx, :]
            long_idx = argmin(abs.(chain.strike .- (short_quote.strike - SPREAD_WIDTH)))
            long_quote = chain[long_idx, :]
            short_strike = Float64(short_quote.strike)
            long_strike = Float64(long_quote.strike)

            long_put = register_instrument!(acc, spy_put(expiry, long_strike))
            short_put = register_instrument!(acc, spy_put(expiry, short_strike))
            push!(registered_options, long_put)
            push!(registered_options, short_put)

            ## Buy the protective leg first, then sell the higher-strike put.
            fill_order!(
                acc,
                Order(oid!(acc), long_put, dt, long_quote.ask, CONTRACTS);
                dt=dt,
                fill_price=long_quote.ask,
                bid=long_quote.bid,
                ask=long_quote.ask,
                last=long_quote.last,
                underlying_price=spot,
            )
            fill_order!(
                acc,
                Order(oid!(acc), short_put, dt, short_quote.bid, -CONTRACTS);
                dt=dt,
                fill_price=short_quote.bid,
                bid=short_quote.bid,
                ask=short_quote.ask,
                last=short_quote.last,
                underlying_price=spot,
            )

            credit = (short_quote.bid - long_quote.ask) * CONTRACTS * short_put.spec.multiplier
            push!(entries, (
                entry_dt=dt,
                expiry=expiry,
                short_strike=short_strike,
                long_strike=long_strike,
                credit=credit,
                margin_used=init_margin_used(acc, usd),
            ))
            push!(open_legs, long_put)
            push!(open_legs, short_put)
            next_entry_idx = i + ENTRY_GAP
        end

        if should_collect(equity_data, dt)
            equity_value = equity(acc, usd)
            collect_equity(dt, equity_value)
            collect_drawdown(dt, equity_value)
        end
    end

    (
        acc=acc,
        usd=usd,
        entries=entries,
        equity_data=equity_data,
        drawdown_data=drawdown_data,
    )
end

result = run_short_put_spread_backtest(market, option_quotes, quote_by_key);
acc = result.acc;
usd = result.usd;
entries = result.entries;
equity_data = result.equity_data;
drawdown_data = result.drawdown_data;

## account and strategy summary
show(acc)

println("Spreads opened: ", nrow(entries))
println("Final equity: \$", round(equity(acc, usd); digits=2))
println("Maximum spread margin used: \$", round(maximum(entries.margin_used); digits=2))
println("Average entry credit: \$", round(mean(entries.credit); digits=2))

#---------------------------------------------------------

# ### Trade log sample

trades = DataFrame(trades_table(acc));
trades[1:min(10, nrow(trades)), [:trade_date, :symbol, :side, :fill_price, :fill_qty, :commission_settle, :cash_delta_settle, :reason]]

#---------------------------------------------------------

# ### Spread entries

entries

#---------------------------------------------------------

# ### Underlying and implied volatility

using Plots

theme(:juno);

plot(
    market.dt,
    market.spot;
    label="SPY synthetic",
    ylabel="underlying price",
    legend=:topleft,
    size=(800, 360),
)
plot!(
    twinx(),
    market.dt,
    market.iv;
    label="implied volatility proxy",
    color=:orange,
    ylabel="IV",
    legend=:topright,
)

#---------------------------------------------------------

# ### Account equity curve

Fastback.plot_equity(equity_data; size=(800, 400))

#---------------------------------------------------------

# ### Account drawdown

Fastback.plot_drawdown(drawdown_data; size=(800, 220))

#---------------------------------------------------------

# ### Summary performance table

DataFrame(performance_summary_table(equity_data; periods_per_year=252))
