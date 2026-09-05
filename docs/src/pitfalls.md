# Pitfalls and gotchas

- `AccountFunding.FullyFunded` forces full-notional margin (no leverage), disallows short exposure, and uses liquidation marks for margin checks so bid/ask spreads do not create synthetic deficits.
- For `MarginRequirement.PercentNotional`, margin rates are equity fractions (IMR/MMR style), not collateral-inclusive ratios: configure a "150% short collateral" rule as `0.50`, not `1.50`.
- Principal-exchange spot short-sale proceeds are not automatically lend-eligible: `accrue_interest!` applies broker-defined short-proceeds rules (`broker_short_proceeds_rates`) to exclude proceeds from lend base and optionally apply a separate rebate.
- Use `update_marks!` to keep equity and margin in sync with prices.
- Expiry/liquidation helpers use stored side-aware quotes (`last_bid`/`last_ask`); keep marks updated with `update_marks!`.
- Listed options are cash-settled and assignment-free in Fastback. SPY-like or AAPL-like examples are synthetic proxies, not OCC/IBKR physical-delivery simulations. See [Options limitations / IBKR mapping](options_limitations.md).
- Multi-currency equity depends on `ExchangeRates` being updated. Once exposure is open, submit FX through `process_step!`; direct account rate mutation is rejected so valuation caches cannot silently go stale.
- FX updates must be representable in both directions as finite `Float64` values; extremely small rates whose reciprocal overflows are rejected without changing the matrix.
- Register non-base currencies via `register_cash_asset!(acc, CashSpec(:EUR))`.
- For variation-margin instruments, fills immediately settle to the current mark basis: execution-to-mark (`mark - fill`) hits cash on the fill, and post-fill `avg_settle_price` is the mark. Settled P&L remains attributed to open exposure until reduction/expiry, so `fill_pnl_settle` (gross realized attribution) can differ from `cash_delta_settle` (same-fill net cash movement).
- All stateful account operations enforce non-decreasing timestamps. Equal timestamps are allowed; backdated fills, marks, financing, and lifecycle operations are rejected.
- Ordinary fills stage their accounting plan before commit, so validation, missing FX, and risk rejection do not require an account snapshot.
- `process_step!` and multi-stage lifecycle operations are fail-stop: an error leaves completed changes in place and sets `acc.poisoned`. Do not recover or continue that account; start from a fresh account or replay from your own checkpoint.
- `StepSchedule` requires at least one unique timestamp. Inputs may be unsorted; the constructor normalizes them chronologically.
- Corporate actions expect raw, unadjusted quotes and have no replay protection. Accrue financing first, apply each action once, then submit the raw ex-action mark at the same timestamp with repeated accrual disabled.
- `OrderRejectError` rejection semantics are mainly for `fill_order!`; expiry/liquidation helpers use internal close-only settlement/liquidation paths instead of exposing normal order lifecycle bypass flags.
- The poisoned flag reports an aborted mutation, not economic bankruptcy; forced closes can still leave negative balances/equity in stressed scenarios.
- `Fastback.plot_*` uses built-in SVG by default. For Plots.jl output, load `Plots` and call `set_plot_backend!(:plots)`; loading Plots alone does not change the backend. Match the selected backend to the target of `!` calls (IO for SVG, `Plots.Plot` for Plots).
