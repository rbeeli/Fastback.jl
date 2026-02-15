# Accounting model and event loop

Fastback is an event-driven accounting engine. You feed it events (marks, FX, funding, expiries),
and it updates balances, equity, and margin deterministically.

## Core objects (quick definitions)

- Account: the central ledger (cash, positions, trades, equity, margin, cashflows).
- Cash: a funding currency (USD, EUR, BTC) with balances and equity tracked per symbol.
- Instrument: contract metadata (symbols, settlement, margin, lifecycle).
- Order: intent to trade at a given time, price, quantity.
- Trade: realized fill produced by `fill_order!`.
- Position: netted exposure per instrument with average entry price.

## Balances vs equity

- Balance is cash-only. Deposits, withdrawals, commissions, and realized P&L change balances.
- Equity is balance plus unrealized P&L for open positions in that currency.
- `update_marks!` recalculates unrealized P&L and updates equity.
- For variation-margin instruments, unrealized P&L is settled into cash on each mark, so balances move as well.

## Realized vs unrealized P&L

- Fill-level additive gross P&L is recorded on `Trade` as `fill_pnl_settle`.
- Net fill cash movement is `cash_delta_settle`.
- Unrealized P&L lives on the `Position` (`pnl_quote`, `pnl_settle`) and is mirrored into equity via `update_marks!` or `process_step!`.

## Settlement styles

- Cash: cash-settled synthetic exposure. Position value is its P&L (no physical delivery).
- VariationMargin: P&L is settled to cash at each mark; position value stays at zero.

## Margin modes and styles

- Account modes: `AccountMode.Cash` enforces fully funded exposure (full notional margin), disallows short exposure, prices requirements from liquidation marks (bid for longs, ask for shorts), and requires withdrawals to respect available funds; `AccountMode.Margin` uses instrument margin settings, with margin priced from marks for `VariationMargin` instruments and from last-trade for other settlement styles.
- Margin modes on instruments: `PercentNotional`, `FixedPerContract`.
- Margining style: `PerCurrency` or `BaseCurrency`, controlling how margin totals are aggregated.

## Event loop

The engine is driven by explicit events.

A typical loop is:

1. Advance time (enforced non-decreasing timestamps): `advance_time!`.
2. Accrue interest and borrow fees as needed: `accrue_interest!`, `accrue_borrow_fees!`.
3. Apply FX updates if you run multi-currency: `update_rate!` (or `process_step!` with `FXUpdate`).
4. Mark positions with bid/ask/last prices: `update_marks!`.
5. Apply funding events (perpetuals): `apply_funding!`.
6. Process expiries (futures): `process_expiries!`.
7. Optionally liquidate to maintenance: `liquidate_to_maintenance!`.
8. Decide and fill new orders for that step: `fill_order!` (after `Order` creation).

You can either:

- Use `process_step!` to run steps 1-7 in one call (recommended for clean, deterministic loops).
- Call the individual functions manually when you need custom ordering.

The [How-to](how_to.md) page shows both styles with code snippets.
