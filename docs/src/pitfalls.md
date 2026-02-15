# Pitfalls and gotchas

- `AccountFunding.FullyFunded` forces full-notional margin (no leverage), disallows short exposure, and uses liquidation marks for margin checks so bid/ask spreads do not create synthetic deficits.
- For `MarginRequirement.PercentNotional`, margin rates are equity fractions (IMR/MMR style), not collateral-inclusive ratios: configure a "150% short collateral" rule as `0.50`, not `1.50`.
- Principal-exchange spot short-sale proceeds are not automatically lend-eligible: `accrue_interest!` applies broker-defined short-proceeds rules (`broker_short_proceeds_rates`) to exclude proceeds from lend base and optionally apply a separate rebate.
- Use `update_marks!` to keep equity and margin in sync with prices.
- Expiry/liquidation helpers use stored side-aware quotes (`last_bid`/`last_ask`); keep marks updated with `update_marks!`.
- Multi-currency equity depends on `ExchangeRates` being updated.
- Register non-base currencies via `register_cash_asset!(acc, CashSpec(:EUR))`.
- For variation-margin instruments, fills immediately settle to the current mark basis: execution-to-mark (`mark - fill`) hits cash on the fill, and post-fill `avg_settle_price` is the mark. Trade-level additive fill amounts are `fill_pnl_settle` (gross) and `cash_delta_settle` (net of commission).
- `OrderRejectError` rejection semantics are mainly for `fill_order!`; expiry/liquidation helpers send close-only synthetic fills (`fill_qty = -position_qty`) with `allow_inactive=true`, so they do not hit incremental-margin rejection (`inc_qty == 0`).
- Fastback currently has no separate bankruptcy state; forced closes can still leave negative balances/equity in stressed scenarios.
- The package contains optionally loaded `Plots.jl` extension functions (some functions additionally require `StatsPlots.jl`).
