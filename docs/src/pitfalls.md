# Pitfalls and gotchas

- `AccountMode.Cash` forces full-notional margin (no leverage), disallows short exposure, and uses liquidation marks for margin checks so bid/ask spreads do not create synthetic deficits.
- Use `update_marks!` to keep equity and margin in sync with prices.
- Expiry settlement requires a finite `mark_price` on the position.
- Multi-currency equity depends on `ExchangeRates` being updated.
- Register non-base currencies via `register_cash_asset!(acc, CashSpec(:EUR))`.
- `OrderRejectError` can be thrown by `fill_order!`, `settle_expiry!`, `process_expiries!`, `liquidate_all!`, and `liquidate_to_maintenance!`.
- The package contains optionally loaded `Plots.jl` extension functions (some functions additionally require `StatsPlots.jl`).
