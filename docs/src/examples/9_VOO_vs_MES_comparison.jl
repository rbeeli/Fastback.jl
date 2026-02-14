# # S&P 500 exposure: VOO on Reg-T margin vs Micro E-mini futures (MES)
#
# This example compares two ways to express S&P 500 exposure:
# 1) VOO ETF on Reg-T margin (asset-settled spot)
# 2) Micro E-mini S&P 500 futures (MES) on variation margin
#
# It runs the same random trade schedule under two leverage factors (`1.0x` and
# `2.0x`) so we can see how leverage changes costs and outcomes for each vehicle.
#
# The data is synthetic but realistic. VOO prices are total-return adjusted
# (dividends already embedded), so no dividend cashflows are applied.

using Fastback
using Dates
using CSV
using DataFrames
using Random

# ---------------------------------------------------------

## IBKR Pro Fixed assumptions (kept compact, not broker-statement exact)
const IBKR_BORROW_SPREAD = 0.015
const IBKR_LEND_SPREAD = 0.005
const IBKR_USD_CREDIT_NO_INTEREST_BALANCE = 10_000.0
const CREDIT_VOO_CASH = true
const CREDIT_MES_CASH = false
const MES_INIT_MARGIN = 2_800.0
const MES_MAINT_MARGIN = 2_421.0
const VOO_REGT_INIT_LONG = 0.50

@inline function ibkr_usd_benchmark(dt::Date)
    @inbounds for i in length(IBKR_USD_BENCHMARK_SCHEDULE):-1:1
        start_dt, rate = IBKR_USD_BENCHMARK_SCHEDULE[i]
        dt >= start_dt && return rate
    end
    IBKR_USD_BENCHMARK_SCHEDULE[1][2]
end

@inline ibkr_usd_borrow_rate(dt::Date) = ibkr_usd_benchmark(dt) + IBKR_BORROW_SPREAD
@inline ibkr_usd_lend_rate(dt::Date) = max(0.0, ibkr_usd_benchmark(dt) - IBKR_LEND_SPREAD)

## IBKR does not pay credit interest on the first USD 10k.
@inline function ibkr_effective_lend_rate(balance::Float64, raw_lend_rate::Float64)
    balance <= IBKR_USD_CREDIT_NO_INTEREST_BALANCE && return 0.0
    raw_lend_rate * (balance - IBKR_USD_CREDIT_NO_INTEREST_BALANCE) / balance
end

# ---------------------------------------------------------

voo_path = "data/voo_tr_1d.csv";
es_path = "data/es_1d.csv";
ibkr_usd_benchmark_schedule_path = "data/ibkr_usd_benchmark_schedule_2025.csv";

## if data path doesn't exist, try to change working directory
isfile(voo_path) || cd("src/examples")

## load synthetic daily data
voo_df = DataFrame(CSV.File(voo_path; dateformat="yyyy-mm-dd"))
es_df = DataFrame(CSV.File(es_path; dateformat="yyyy-mm-dd"))

@assert nrow(voo_df) == nrow(es_df)

## load USD benchmark schedule for 2025
## Source: IBKR monthly interest-rate export (Jun-Dec 2025); Jan-May approximated
## at 4.33% as unchanged pre-cut.
const IBKR_USD_BENCHMARK_SCHEDULE = Tuple(
    (Date(row.start_dt), Float64(row.usd_benchmark))
    for row in CSV.File(ibkr_usd_benchmark_schedule_path; dateformat="yyyy-mm-dd")
)
@assert !isempty(IBKR_USD_BENCHMARK_SCHEDULE)

# ---------------------------------------------------------

## helper: per-order commissions (IBKR Pro Fixed approximations)

function ibkr_equity_commission_fixed(qty, fill_price)
    qty_abs = abs(qty)
    qty_abs == 0.0 && return 0.0
    per_share = 0.005
    min_commission = 1.00
    max_commission = 0.01 * qty_abs * abs(fill_price) # 1% of trade value cap
    min(max(min_commission, qty_abs * per_share), max_commission)
end

function ibkr_futures_commission_fixed(qty, _fill_price)
    qty_abs = abs(qty)
    qty_abs == 0.0 && return 0.0
    exec_fixed = 0.85
    exchange_fee = 0.35
    regulatory_fee = 0.02
    qty_abs * (exec_fixed + exchange_fee + regulatory_fee)
end

## helper: discrete quantity for a target notional
function qty_for_notional(inst, price, notional)
    raw = notional / (price * inst.multiplier)
    Float64(max(0, floor(Int, raw)))
end

## helper: shared backtest loop
function run_backtest!(
    acc,
    inst,
    df,
    trade_lookup;
    target_notional,
    commission_fn,
    lend_interest_enabled=true,
)
    usd = cash_asset(acc, :USD)

    for (i, row) in enumerate(eachrow(df))
        dt = row.dt
        bid = row.bid
        ask = row.ask
        last = row.last

        raw_lend = lend_interest_enabled ? ibkr_usd_lend_rate(dt) : 0.0
        bal = cash_balance(acc, usd)
        lend = (lend_interest_enabled && bal > 0.0) ? ibkr_effective_lend_rate(bal, raw_lend) : 0.0
        set_interest_rates!(acc, :USD;
            borrow=ibkr_usd_borrow_rate(dt),
            lend=lend,
        )

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
                fill_order!(acc, order;
                    dt=dt,
                    fill_price=fill_price,
                    bid=bid,
                    ask=ask,
                    last=last,
                    commission=commission_fn(delta_qty, fill_price),
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
        fill_order!(acc, order;
            dt=last_row.dt,
            fill_price=fill_price,
            bid=last_row.bid,
            ask=last_row.ask,
            last=last_row.last,
            commission=commission_fn(-pos.quantity, fill_price),
        )
    end

    acc
end

## helper: deterministic random trade schedule (~20 toggles in/out)
function make_trade_lookup(n_rows; n_events=20, seed=2025)
    rng = MersenneTwister(seed)
    pool = collect(15:(n_rows - 15))
    trade_indices = sort(pool[randperm(rng, length(pool))[1:n_events]])
    Dict(idx => i for (i, idx) in enumerate(trade_indices))
end

# ---------------------------------------------------------

## account + instrument builders

function build_voo_account(initial_cash)
    acc = Account(; mode=AccountMode.Margin, base_currency=CashSpec(:USD), time_type=Date)
    deposit!(acc, :USD, initial_cash)

    voo = register_instrument!(acc, spot_instrument(
        :VOO, :VOO, :USD;
        time_type=Date,
        base_tick=1.0,
        base_digits=0,
        quote_tick=0.01,
        quote_digits=2,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=VOO_REGT_INIT_LONG,
        margin_init_short=1.35,
        margin_maint_long=0.25,
        margin_maint_short=1.20,
    ))

    acc, voo
end

function build_mes_account(initial_cash)
    acc = Account(; mode=AccountMode.Margin, base_currency=CashSpec(:USD), time_type=Date)
    deposit!(acc, :USD, initial_cash)

    es = register_instrument!(acc, future_instrument(
        :MES, :MES, :USD;
        time_type=Date,
        base_tick=1.0,
        base_digits=0,
        quote_tick=0.25,
        quote_digits=2,
        multiplier=5.0,
        margin_mode=MarginMode.FixedPerContract,
        margin_init_long=MES_INIT_MARGIN,
        margin_init_short=MES_INIT_MARGIN,
        margin_maint_long=MES_MAINT_MARGIN,
        margin_maint_short=MES_MAINT_MARGIN,
        expiry=Date(2026, 3, 20),
    ))

    acc, es
end

# ---------------------------------------------------------

## summarize results (costs + net equity)

function summarize(acc, label, initial_cash, leverage_factor)
    end_equity = equity(acc, cash_asset(acc, :USD))
    pnl = end_equity - initial_cash
    commissions = sum(t.commission_settle for t in acc.trades, init=0.0)
    lend_interest = sum(cf.amount for cf in acc.cashflows if cf.kind == CashflowKind.LendInterest, init=0.0)
    borrow_interest = -sum(cf.amount for cf in acc.cashflows if cf.kind == CashflowKind.BorrowInterest, init=0.0)
    net_interest = lend_interest - borrow_interest
    borrow_fees = sum(cf.amount for cf in acc.cashflows if cf.kind == CashflowKind.BorrowFee, init=0.0)
    interest_cost = max(0.0, -net_interest)

    (
        leverage=leverage_factor,
        instrument=label,
        target_notional=round(leverage_factor * initial_cash, digits=2),
        trades=length(acc.trades),
        end_equity=round(end_equity, digits=2),
        pnl=round(pnl, digits=2),
        commissions=round(commissions, digits=2),
        lend_interest=round(lend_interest, digits=2),
        borrow_interest=round(borrow_interest, digits=2),
        net_interest=round(net_interest, digits=2),
        interest_cost=round(interest_cost, digits=2),
        borrow_fees=round(borrow_fees, digits=2),
    )
end

# ---------------------------------------------------------

## run scenarios

initial_cash = 200_000.0
leverage_factors = (1.0, 2.0)
trade_lookup = make_trade_lookup(nrow(voo_df); n_events=20, seed=2025)

rows = []
for leverage_factor in leverage_factors
    target_notional = leverage_factor * initial_cash

    acc_voo, voo = build_voo_account(initial_cash)
    run_backtest!(acc_voo, voo, voo_df, trade_lookup;
        target_notional=target_notional,
        commission_fn=ibkr_equity_commission_fixed,
        lend_interest_enabled=CREDIT_VOO_CASH,
    )
    push!(rows, summarize(acc_voo, "VOO (Reg-T margin)", initial_cash, leverage_factor))

    acc_es, es = build_mes_account(initial_cash)
    run_backtest!(acc_es, es, es_df, trade_lookup;
        target_notional=target_notional,
        commission_fn=ibkr_futures_commission_fixed,
        lend_interest_enabled=CREDIT_MES_CASH,
    )
    push!(rows, summarize(acc_es, "MES (futures margin)", initial_cash, leverage_factor))
end

summary = DataFrame(rows)
sort!(summary, [:leverage, :instrument])
display(summary)

# ---------------------------------------------------------

## compact view: leverage effect within each instrument
leverage_effect_wide = combine(groupby(summary, :instrument)) do sdf
    s1 = sdf[sdf.leverage .== 1.0, :]
    s2 = sdf[sdf.leverage .== 2.0, :]
    @assert nrow(s1) == 1 && nrow(s2) == 1

    (
        pnl_1x=s1.pnl[1],
        pnl_2x=s2.pnl[1],
        pnl_delta_2x_minus_1x=round(s2.pnl[1] - s1.pnl[1], digits=2),
        comm_1x=s1.commissions[1],
        comm_2x=s2.commissions[1],
        lend_interest_1x=s1.lend_interest[1],
        lend_interest_2x=s2.lend_interest[1],
        borrow_interest_1x=s1.borrow_interest[1],
        borrow_interest_2x=s2.borrow_interest[1],
        net_interest_1x=s1.net_interest[1],
        net_interest_2x=s2.net_interest[1],
    )
end

metric_cols = names(leverage_effect_wide, Not(:instrument))
leverage_effect = DataFrame(metric=String.(metric_cols))
for row in eachrow(leverage_effect_wide)
    leverage_effect[!, Symbol(row.instrument)] = [row[col] for col in metric_cols]
end

display(leverage_effect)

# ---------------------------------------------------------

# Notes:
# - VOO prices are total-return adjusted (no separate dividend cashflows).
# - MES is treated as a continuous contract; expiry is set beyond the test window.
# - Financing uses a simplified IBKR Pro model:
#   `borrow = usd_benchmark + 1.50%`, `lend = max(usd_benchmark - 0.50%, 0)`.
# - For credit interest, first USD 10k is assumed to earn 0% (effective-rate approximation).
# - `CREDIT_MES_CASH=false` approximates no interest on futures-segment idle cash
#   unless an explicit sweep is modeled.
# - `borrow_interest` is reported as a positive paid amount; `net_interest = lend_interest - borrow_interest`.
# - Margin/commission numbers are simplified placeholders for comparison only.
