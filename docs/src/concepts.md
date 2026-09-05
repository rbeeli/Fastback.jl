# Accounting model and event loop

Fastback is an event-driven accounting engine. You feed it events (marks, FX, funding, expiries),
and it updates balances, equity, and margin deterministically.

## Core objects (quick definitions)

- Account: the central ledger (cash, positions, trades, equity, margin, cashflows).
- Cash: a funding currency (USD, EUR, BTC) with balances and equity tracked per symbol.
- InstrumentSpec: immutable contract metadata (symbols, settlement, margin, lifecycle).
- Instrument: account-bound handle with instrument/cash indices resolved at registration.
- Order: intent to trade at a given time, price, quantity.
- Trade: realized fill produced by `fill_order!`.
- Position: netted exposure per instrument with average entry price.

## Balances vs equity

- Balance is cash-only. Deposits, withdrawals, commissions, and realized P&L change balances.
- Equity is balance plus unrealized P&L for open positions in that currency.
- `update_marks!` recalculates unrealized P&L and updates equity.
- For variation-margin instruments, unrealized P&L is settled into cash on each mark, so balances move as well.
- Principal-exchange spot shorts increase cash balance by short-sale proceeds. Interest accrual can exclude those proceeds from the regular lend base and optionally apply a separate short-proceeds rebate rate via broker configuration.

## Realized vs unrealized P&L

- Fill-level additive gross P&L is recorded on `Trade` as `fill_pnl_settle`. For variation-margin contracts, settled mark-to-market is carried with the open exposure and attributed proportionally when that exposure is reduced or expires.
- Net fill cash movement is `cash_delta_settle`.
- Unrealized P&L lives on the `Position` (`pnl_quote`, `pnl_settle`) and is mirrored into equity via `update_marks!` or `process_step!`.

## Settlement styles

- PrincipalExchange: fills exchange principal; open position value is marked notional (`qty * price * multiplier`).
- VariationMargin: mark-to-market P&L is settled into cash at each mark; open position value stays at zero. Cash timing and trade-P&L attribution are deliberately separate, so an opening execution-to-mark settlement can move cash while the opening trade reports zero realized P&L.

`AccountFunding.FullyFunded` is a funding policy, not a settlement style.

## Listed options model

Fastback treats listed options as quote-driven, cash-settled contracts. This is deliberate
even when examples use SPY-like or AAPL-like symbols. Early exercise, short assignment,
physical delivery, pin risk, and broker-specific exercise processing are not modeled.

See [Options limitations / IBKR mapping](options_limitations.md) before using equity-option
examples as a proxy for broker or OCC behavior.

## Margin requirements and styles

- Funding policies: `AccountFunding.FullyFunded` enforces fully funded exposure (full notional margin), disallows short exposure, prices requirements from liquidation marks (bid for longs, ask for shorts), and requires withdrawals to respect available funds; `AccountFunding.Margined` uses instrument margin settings, with margin priced from marks for `VariationMargin` instruments and from last-trade for other settlement styles.
- Margin requirements on instruments: `PercentNotional`, `FixedPerContract`.
- `PercentNotional` uses IMR/MMR-style equity fractions of notional: `required_margin = rate * abs(qty) * abs(price) * multiplier`.
- For short rules expressed as total collateral (for example "150% of short notional"), convert to equity fraction before configuring Fastback: `150% -> 0.50`.
- Margin aggregation: `PerCurrency` or `BaseCurrency`, controlling how margin totals are aggregated.

## Event loop

The engine is driven by explicit events.

A typical loop is:

1. Advance time (enforced non-decreasing timestamps): `advance_time!`.
2. Accrue interest and borrow fees as needed: `accrue_interest!`, `accrue_borrow_fees!`.
3. Apply FX updates if you run multi-currency through `process_step!` with `FXUpdate` once exposure is open.
4. Mark positions with bid/ask/last prices: `update_marks!`.
5. Apply funding events (perpetuals): `apply_funding!`.
6. Process expiries: `process_expiries!` closes short options first, futures second, and long options last.
7. Optionally liquidate to maintenance: `liquidate_to_maintenance!`.
8. Decide and fill new orders for that step: `create_order!` advances account time when the order is accepted, then `fill_order!` applies its execution.

You can either:

- Use `process_step!` to run steps 1-7 in one call (recommended for clean, deterministic loops).
- Call the individual functions manually when you need custom ordering.

Within a step, repeated FX routes, instrument marks, and option-underlying marks
use the final observation for each key. Reusable indices coalesce them in linear
time without copying account state. Ordered funding and lifecycle work follows
the market updates. Direct `update_rate!(acc, ...)` is only
allowed while the account is flat, because open positions require coordinated
revaluation.

For option-chain snapshots, pass all marks for a timestamp in one `process_step!`
call. Mixed long/short groups recompute margin once after changed inputs are
applied; groups containing only long options update each position's margin by
delta. Unchanged margin inputs retain cached totals while quote timestamps still
advance. Calling `update_marks!` separately preserves intermediate account states. Reuse the event vectors
between steps with `empty!`/`push!` or overwrite existing entries as new data arrives.

Default financing and expiry processing use indices of relevant positions. Cash
interest reuses short-sale proceeds until exposure or entry bases change, and FX
updates refresh only open positions dependent on those currency pairs. An indexed
expiry schedule avoids shifting the portfolio on each open/close, and bulk
settlements compact their indices once. These indices are maintained by the
trading and corporate-action APIs. Treat position quantities,
entry bases, and registered instrument indices as engine-managed state.

Target-weight rebalancing reuses account-owned planning buffers and considers the
union of target and open positions. Returned trade and suppression vectors remain
caller-owned and are unaffected by later rebalances.

For runs that only need account state and aggregate trade counts, construct the
account with `track_trades=false` and optionally `track_cashflows=false`. Ordinary
spot and variation-margin fills can then avoid allocating temporary orders after
compilation. Fills return `nothing` when trade tracking is disabled; analyses and
collectors that require trade history still need `track_trades=true`.

`process_step!` is fail-stop. If any phase throws, completed earlier phases stay
applied and `acc.poisoned` is set. Discard that account; a later time-advancing
operation throws `AccountPoisonedError`.

The [How-to](how_to.md) page shows both styles with code snippets.
