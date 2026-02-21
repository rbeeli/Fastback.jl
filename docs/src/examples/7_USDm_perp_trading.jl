# # USD-M perpetual (Binance-style) example
#
# This example shows how to backtest a USD-M perpetual swap using `process_step!`
# with mark updates and funding events. The CSV data is synthetic but shaped
# like Binance USD-M: hourly bid/ask/last prices and a funding rate applied
# every 8 hours (non-zero rows).

using Fastback
using Dates
using CSV
using DataFrames
using Statistics

# ---------------------------------------------------------

## load synthetic USD-M perp data
## columns: dt, bid, ask, last, funding_rate

data_path = "data/usdm_perp_1h.csv";

## if data path doesn't exist, try to change working directory
isfile(data_path) || cd("src/examples")

## parse CSV (hourly rows)
df = DataFrame(CSV.File(data_path; dateformat="yyyy-mm-dd HH:MM:SS"));
sort!(df, :dt);

## quick sanity check
first(df, 5)

# ---------------------------------------------------------

## create a margined account funded in USDT
acc = Account(;
    funding=AccountFunding.Margined,
    base_currency=CashSpec(:USDT),
    broker=BinanceBroker(; maker_derivatives=0.0004, taker_derivatives=0.0004),
);
usdt = cash_asset(acc, :USDT)
deposit!(acc, :USDT, 10_000.0);

## register a USD-M perpetual (variation margin, cash-settled)
perp = register_instrument!(acc, perpetual_instrument(
    Symbol("BTCUSDT-PERP"), :BTC, :USDT;
    margin_requirement=MarginRequirement.PercentNotional,
    margin_init_long=0.10,
    margin_init_short=0.10,
    margin_maint_long=0.05,
    margin_maint_short=0.05,
    base_tick=0.001,
    quote_tick=0.1,
    base_digits=3,
    quote_digits=1,
));

## data collector for account equity and drawdowns (sampling every hour)
collect_equity, equity_data = periodic_collector(Float64, Hour(1));
collect_drawdown, drawdown_data = drawdown_collector(DrawdownMode.Percentage, Hour(1));

# ---------------------------------------------------------

## simple trend-following strategy
## - compute a 24h moving average
## - go long if price is >0.2% above MA
## - go short if price is >0.2% below MA
## - target ~3x notional leverage

window = 24;
deadband = 0.002;
leverage_target = 3.0;

@inline fill_price_for_qty(qty, bid, ask) = qty > 0.0 ? ask : bid

for i in 1:nrow(df)
    row = df[i, :]
    dt = row.dt
    bid = row.bid
    ask = row.ask
    last = row.last
    funding_rate = row.funding_rate

    ## apply marks and funding for this step
    marks = [MarkUpdate(perp.index, bid, ask, last)]
    funding = funding_rate == 0.0 ? nothing : [FundingUpdate(perp.index, funding_rate)]
    process_step!(acc, dt; marks=marks, funding=funding, liquidate=true)

    ## trade after marks/funding (positions at funding timestamp are used)
    if i >= window
        ma = mean(@view df.last[i-window+1:i])
        signal = last > (1 + deadband) * ma ? 1.0 : (last < (1 - deadband) * ma ? -1.0 : 0.0)

        pos = get_position(acc, perp)
        target_notional = signal == 0.0 ? 0.0 : signal * leverage_target * equity(acc, usdt)
        target_qty = calc_base_qty_for_notional(perp, last, target_notional)
        delta_qty = target_qty - pos.quantity

        if abs(delta_qty) >= (perp.base_tick / 2)
            fill_price = fill_price_for_qty(delta_qty, bid, ask)
            order = Order(oid!(acc), perp, dt, fill_price, delta_qty)
            fill_order!(acc, order; dt=dt, fill_price=fill_price, bid=bid, ask=ask, last=last)
        end
    end

    ## collect data for plotting
    if should_collect(equity_data, dt)
        eq = equity(acc, usdt)
        collect_equity(dt, eq)
        collect_drawdown(dt, eq)
    end
end

## close any remaining position at the end
row = df[end, :]
pos = get_position(acc, perp)
if pos.quantity != 0.0
    close_qty = -pos.quantity
    close_fill_price = fill_price_for_qty(close_qty, row.bid, row.ask)
    order = Order(oid!(acc), perp, row.dt, close_fill_price, close_qty)
    fill_order!(acc, order; dt=row.dt, fill_price=close_fill_price, bid=row.bid, ask=row.ask, last=row.last)
end

## summarize funding P&L
funding_pnl = sum(cf.amount for cf in acc.cashflows if cf.kind == CashflowKind.Funding)
println("Funding P&L (USDT): ", round(funding_pnl, digits=2))

## fill-level P&L decomposition (variation margin)
gross_fill_settled_pnl = sum(t.fill_pnl_settle for t in acc.trades; init=0.0)
commissions = sum(t.commission_settle for t in acc.trades; init=0.0)
net_fill_cash = sum(t.cash_delta_settle for t in acc.trades; init=0.0)
println("Gross fill settled P&L (USDT): ", round(gross_fill_settled_pnl, digits=2))
println("Commissions (USDT): ", round(commissions, digits=2))
println("Net fill cash delta (USDT): ", round(net_fill_cash, digits=2))

## print account summary
show(acc)

# ---------------------------------------------------------

# ### Plot account equity curve

using Plots

theme(:juno)

Fastback.plot_equity(equity_data; size=(800, 400))

# ---------------------------------------------------------

# ### Plot account equity drawdown curve

Fastback.plot_drawdown(drawdown_data; size=(800, 200))

# ---------------------------------------------------------

# ### Plot cashflows by type

Fastback.plot_cashflows(acc)
