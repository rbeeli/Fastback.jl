# # S&P 500 exposure: VOO on Reg-T margin vs Micro E-mini futures (MES)
#
# This example compares two ways to express S&P 500 exposure:
# 1) VOO ETF on Reg-T margin (cash-settled spot)
# 2) Micro E-mini S&P 500 futures (MES) on variation margin
#
# The data is synthetic but realistic. VOO prices are **total-return adjusted**
# (dividends already embedded), so no dividend cashflows are applied.
#
# The goal is to compare **costs** (commissions + financing) for the same
# notional exposure using a simple random trade schedule (~20 trades).

using Fastback
using Dates
using CSV
using DataFrames
using Random

# ---------------------------------------------------------

## load synthetic daily data
voo_path = "data/voo_tr_1d.csv";
es_path = "data/es_1d.csv";

isfile(voo_path) || cd("src/examples")

voo_df = DataFrame(CSV.File(voo_path; dateformat="yyyy-mm-dd"))
es_df = DataFrame(CSV.File(es_path; dateformat="yyyy-mm-dd"))

@assert nrow(voo_df) == nrow(es_df)

# ---------------------------------------------------------

## helper: per-order commissions (simple IBKR-like approximations)

function ibkr_equity_commission(qty)
    per_share = 0.0035   # USD per share
    min_commission = 1.00
    max(min_commission, abs(qty) * per_share)
end

function ibkr_futures_commission(qty)
    per_contract = 1.25  # USD per contract (all-in)
    abs(qty) * per_contract
end

## helper: discrete quantity for a target notional
function qty_for_notional(inst, price, notional)
    raw = notional / (price * inst.multiplier)
    Float64(max(0, floor(Int, raw)))
end

## helper: backtest loop
function run_backtest!(acc, inst, df, trade_lookup; target_notional, commission_fn)
    for (i, row) in enumerate(eachrow(df))
        dt = row.dt
        bid = row.bid
        ask = row.ask
        last = row.last

        marks = [MarkUpdate(inst.index, bid, ask, last)]
        process_step!(acc, dt; marks=marks, liquidate=true)

        event_no = get(trade_lookup, i, 0)
        if event_no != 0
            target_qty = isodd(event_no) ? qty_for_notional(inst, last, target_notional) : 0.0
            pos = get_position(acc, inst)
            delta_qty = target_qty - pos.quantity

            if delta_qty != 0.0
                fill_price = delta_qty > 0 ? ask : bid
                order = Order(oid!(acc), inst, dt, fill_price, delta_qty)
                commission = commission_fn(delta_qty)
                fill_order!(acc, order;
                    dt=dt,
                    fill_price=fill_price,
                    bid=bid,
                    ask=ask,
                    last=last,
                    commission=commission,
                )
            end
        end
    end

    ## close any remaining position at the end
    last_row = df[end, :]
    pos = get_position(acc, inst)
    if pos.quantity != 0.0
        fill_price = pos.quantity > 0 ? last_row.bid : last_row.ask
        order = Order(oid!(acc), inst, last_row.dt, fill_price, -pos.quantity)
        commission = commission_fn(-pos.quantity)
        fill_order!(acc, order;
            dt=last_row.dt,
            fill_price=fill_price,
            bid=last_row.bid,
            ask=last_row.ask,
            last=last_row.last,
            commission=commission,
        )
    end

    acc
end

# ---------------------------------------------------------

## shared backtest configuration
initial_cash = 200_000.0
notional_target = 2.0 * initial_cash  # Reg-T: ~2x buying power on equities

rng = MersenneTwister(2025)
pool = collect(15:(nrow(voo_df) - 15))
trade_indices = sort(pool[randperm(rng, length(pool))[1:20]])
trade_lookup = Dict(idx => i for (i, idx) in enumerate(trade_indices))

# ---------------------------------------------------------

## account + instrument: VOO (Reg-T margin)

acc_voo = Account(; mode=AccountMode.Margin, base_currency=:USD, time_type=Date)
USD_voo = Cash(:USD; digits=2)
register_cash_asset!(acc_voo, USD_voo)
deposit!(acc_voo, USD_voo, initial_cash)
set_interest_rates!(acc_voo, :USD; borrow=0.06, lend=0.015)

# IBKR-style: VOO (SMART/ARCA), USD stock, 0.01 tick
# Reg-T margin (approx): 50% init, 25% maint for longs
voo = register_instrument!(acc_voo, margin_spot_instrument(
    :VOO, :VOO, :USD;
    time_type=Date,
    base_tick=1.0,
    base_digits=0,
    quote_tick=0.01,
    quote_digits=2,
    margin_mode=MarginMode.PercentNotional,
    margin_init_long=0.50,
    margin_init_short=1.50,
    margin_maint_long=0.25,
    margin_maint_short=1.30,
))

# ---------------------------------------------------------

## account + instrument: MES (Micro E-mini S&P 500 futures)

acc_es = Account(; mode=AccountMode.Margin, base_currency=:USD, time_type=Date)
USD_es = Cash(:USD; digits=2)
register_cash_asset!(acc_es, USD_es)
deposit!(acc_es, USD_es, initial_cash)
set_interest_rates!(acc_es, :USD; borrow=0.06, lend=0.015)

# IBKR-style: MES (GLOBEX), USD, 0.25 tick, multiplier 5
# Margin is fixed per contract (values are realistic placeholders)
es = register_instrument!(acc_es, future_instrument(
    :MES, :MES, :USD;
    time_type=Date,
    base_tick=1.0,
    base_digits=0,
    quote_tick=0.25,
    quote_digits=2,
    multiplier=5.0,
    margin_mode=MarginMode.FixedPerContract,
    margin_init_long=1_250.0,
    margin_init_short=1_250.0,
    margin_maint_long=1_150.0,
    margin_maint_short=1_150.0,
    expiry=Date(2026, 3, 20),
))

# ---------------------------------------------------------

## run both backtests with the same trade schedule

run_backtest!(acc_voo, voo, voo_df, trade_lookup;
    target_notional=notional_target,
    commission_fn=ibkr_equity_commission,
)

run_backtest!(acc_es, es, es_df, trade_lookup;
    target_notional=notional_target,
    commission_fn=ibkr_futures_commission,
)

# ---------------------------------------------------------

## summarize results (costs + net equity)

function summarize(acc, label, initial_cash)
    end_equity = equity(acc, :USD)
    pnl = end_equity - initial_cash
    commissions = sum(t.commission_settle for t in acc.trades, init=0.0)
    interest = sum(cf.amount for cf in acc.cashflows if cf.kind == CashflowKind.Interest, init=0.0)
    borrow_fees = sum(cf.amount for cf in acc.cashflows if cf.kind == CashflowKind.BorrowFee, init=0.0)
    interest_cost = max(0.0, -interest)

    return (
        instrument=label,
        trades=length(acc.trades),
        end_equity=round(end_equity, digits=2),
        pnl=round(pnl, digits=2),
        commissions=round(commissions, digits=2),
        interest_cost=round(interest_cost, digits=2),
        borrow_fees=round(borrow_fees, digits=2),
    )
end

summary = DataFrame([
    summarize(acc_voo, "VOO (Reg-T margin)", initial_cash),
    summarize(acc_es, "MES (futures margin)", initial_cash),
])

summary

# ---------------------------------------------------------

# Notes:
# - VOO prices are total-return adjusted (no separate dividend cashflows).
# - MES is treated as a continuous contract; expiry is set beyond the test window.
# - Margin/commission numbers are realistic placeholders for comparison only.
