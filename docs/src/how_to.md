# How-to recipes

Short, practical snippets for common workflows.

## Drive the engine with `process_step!`

```julia
using Fastback
using Dates

ledger = CashLedger()
usd = register_cash_asset!(ledger, :USD)
eur = register_cash_asset!(ledger, :EUR)
er = ExchangeRates()
add_asset!(er, usd)
add_asset!(er, eur)
acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=usd, exchange_rates=er)
deposit!(acc, usd, 10_000.0)
deposit!(acc, eur, 5_000.0)

inst = register_instrument!(acc, perpetual_instrument(
    :BTCUSD, :BTC, :USD;
    margin_mode=MarginMode.PercentNotional,
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
- FX updates are applied on the account's `ExchangeRates`.
- Caller is responsible for keeping `ExchangeRates` in sync with ledger cash assets via `add_asset!`.
- Setup order: register all cash in `CashLedger`, add them to `ExchangeRates`, then create `Account` and fund it.
- Orders are filled separately with `fill_order!`.

## Manual event loop

Use this when you need custom ordering or extra side effects per step.

```julia
# advance time (accrues interest/borrow fees by default)
advance_time!(acc, dt)

# optional FX update
update_rate!(er, eur, usd, 1.07)

# mark positions (also revalues equity for open positions)
update_marks!(acc, inst, dt, bid, ask, last)

# funding and expiries (if applicable)
apply_funding!(acc, inst, dt; funding_rate=funding_rate)
process_expiries!(acc, dt)

# optional liquidation pass
is_under_maintenance(acc) && liquidate_to_maintenance!(acc, dt)
```

## Multi-currency equity in base currency

```julia
ledger = CashLedger()
usd = register_cash_asset!(ledger, :USD)
eur = register_cash_asset!(ledger, :EUR)
er = ExchangeRates()
add_asset!(er, usd)
add_asset!(er, eur)
acc = Account(; mode=AccountMode.Margin, ledger=ledger, base_currency=usd, exchange_rates=er)
deposit!(acc, usd, 10_000.0)
deposit!(acc, eur, 5_000.0)

update_rate!(er, eur, usd, 1.07)
equity_base_ccy(acc) # total equity in USD
```

## Use Tables.jl outputs

```julia
using DataFrames

df_trades = DataFrame(trades_table(acc))
df_positions = DataFrame(positions_table(acc))
df_balances = DataFrame(balances_table(acc))
df_equities = DataFrame(equities_table(acc))
df_cashflows = DataFrame(cashflows_table(acc))
```
