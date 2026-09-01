# How-to recipes

Short, practical snippets for common workflows.

## Drive the engine with `process_step!`

```julia
using Fastback
using Dates

er = ExchangeRates()
acc = Account(;
    broker=FlatFeeBroker(pct=0.001),
    funding=AccountFunding.Margined,
    base_currency=CashSpec(:USD),
    exchange_rates=er,
)
usd = cash_asset(acc, :USD)
eur = register_cash_asset!(acc, CashSpec(:EUR))
deposit!(acc, usd, 10_000.0)
deposit!(acc, eur, 5_000.0)

inst = register_instrument!(acc, perpetual_instrument(
    :BTCUSD, :BTC, :USD;
    margin_requirement=MarginRequirement.PercentNotional,
    margin_init_long=0.10,
    margin_init_short=0.10,
    margin_maint_long=0.05,
    margin_maint_short=0.05,
))

dt = DateTime(2024, 1, 1, 0)
bid, ask, last = 100.0, 100.5, 100.2
funding_rate = 0.0001
eurusd = 1.07

fx_updates = [FXUpdate(eur, usd, eurusd)]
marks = [MarkUpdate(inst.index, bid, ask, last)]
funding = [FundingUpdate(inst.index, funding_rate)]

process_step!(acc, dt; fx_updates=fx_updates, marks=marks, funding=funding, expiries=true, liquidate=false)
```

Notes:

- `process_step!` enforces non-decreasing timestamps and accrues interest/borrow fees before same-step FX/mark updates.
- Repeated FX, mark, and option-underlying observations are coalesced by reusable indices in linear time without an account-wide snapshot.
- A failed step or multi-stage lifecycle operation keeps completed changes, sets `acc.poisoned`, and must terminate that account's run.
- FX updates are applied on the account's `ExchangeRates` and revalue dependent position and margin caches.
- Cash registration is account-owned: use `register_cash_asset!(acc, CashSpec(:EUR))` and `ExchangeRates` is resized automatically.
- Setup order: create `Account`, register additional cash assets, set FX rates, then fund it.
- Set `track_trades=false` and/or `track_cashflows=false` on `Account` when you only need final state and want lower history overhead.
- Orders are created separately with `create_order!`, which validates and advances account time, then filled with `fill_order!`.
- For `MarginRequirement.PercentNotional`, `margin_init_*` / `margin_maint_*` are equity fractions of notional (`0.10` means 10%).

## Manual event loop

Use this when you need custom ordering or extra side effects per step.

```julia
# advance time (accrues interest/borrow fees by default)
advance_time!(acc, dt)

# Once exposure is open, apply FX and marks together through process_step!.
process_step!(
    acc,
    dt;
    fx_updates=[FXUpdate(eur, usd, 1.07)],
    marks=[MarkUpdate(inst.index, bid, ask, last)],
    expiries=false,
    accrue_interest=false,
    accrue_borrow_fees=false,
)

# funding and expiries (if applicable)
apply_funding!(acc, inst, dt; funding_rate=funding_rate)
process_expiries!(acc, dt)

# optional liquidation pass
is_under_maintenance(acc) && liquidate_to_maintenance!(acc, dt)
```

Expiry batches settle short options first, futures second, and long options
last, preserving registration order within each group.

## Multi-currency equity in base currency

```julia
er = ExchangeRates()
acc = Account(;
    broker=FlatFeeBroker(pct=0.001),
    funding=AccountFunding.Margined,
    base_currency=CashSpec(:USD),
    exchange_rates=er,
)
usd = cash_asset(acc, :USD)
eur = register_cash_asset!(acc, CashSpec(:EUR))
deposit!(acc, usd, 10_000.0)
deposit!(acc, eur, 5_000.0)

update_rate!(er, eur, usd, 1.07)
equity_base_ccy(acc) # total equity in USD
```

The direct rate update above is setup for a flat account. With open exposure,
use `process_step!(...; fx_updates=...)`; direct `update_rate!(acc, ...)` rejects
the update rather than leaving cached valuations stale.

## Apply a spot split or cash dividend

Corporate-action inputs and later marks must be raw, unadjusted market data.
The dividend is quote currency per pre-action unit, and short positions are
debited automatically.

```julia
apply_spot_corporate_action!(
    acc,
    stock,
    ex_date;
    split_factor=2.0,              # new units per old unit
    cash_dividend_per_unit=0.50,
)
```

The operation adjusts position bases and the preceding raw quotes mechanically,
records `CashflowKind.CashDividend`, and preserves equity before subsequent
market movement. A failure poisons the account; completed changes are not rolled
back. It does not accrue financing or deduplicate replayed actions.

## Use Tables.jl outputs

```julia
using DataFrames

df_trades = DataFrame(trades_table(acc))
df_positions = DataFrame(positions_table(acc))
df_balances = DataFrame(balances_table(acc))
df_equities = DataFrame(equities_table(acc))
df_cashflows = DataFrame(cashflows_table(acc))
```

Notes:

- `df_trades.fill_pnl_settle` is the additive gross fill-settled P&L column.
- `df_trades.cash_delta_settle` is the additive net cash movement per fill.
