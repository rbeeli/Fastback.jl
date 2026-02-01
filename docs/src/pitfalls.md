# Pitfalls and gotchas

- Cash accounts only accept asset-settled instruments (use `spot_instrument` or `settlement=SettlementStyle.Asset`).
- Cash-settled or variation-margin instruments require `AccountMode.Margin`.
- Use `update_marks!` to keep equity and margin in sync with prices.
- Expiry settlement requires a finite `mark_price` on the position.
- Multi-currency equity depends on `SpotExchangeRates` being present and updated.
- `OrderRejectError` can be thrown by `fill_order!`, `settle_expiry!`, `process_expiries!`, `liquidate_all!`, and `liquidate_to_maintenance!`.
- The package contains optionally loaded `Plots.jl` extension functions (some functions additionally require `StatsPlots.jl`).
