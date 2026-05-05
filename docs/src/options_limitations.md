# Options limitations / IBKR mapping

Fastback's listed option support is deterministic and accounting-focused. It is useful for
researching premium flows, mark-to-market P&L, spread margin behavior, expiry cashflows,
and liquidation mechanics. It is not a full OCC, exchange, or broker lifecycle simulator.

## What Fastback Models

- Quote-driven listed option positions with bid, ask, and last marks.
- Premium cash accounting in the option settlement currency.
- Underlying marks through `OptionUnderlyingUpdate` and `update_option_underlying_price!`.
- Cash settlement at intrinsic value through `settle_option_expiry!` and `process_expiries!`.
- Short-option margin plus bounded multi-leg margin relief for same-underlying option groups.
- Atomic package preflight through `fill_option_strategy!`.
- Broker-profile commissions and financing where configured, for example through `IBKRProFixedBroker`.

## Important Limitations

All option expiries in Fastback are cash-settled by the engine. This applies even when the
symbols and examples look like SPY, AAPL, or other US equity or ETF options.

Fastback does not currently model:

- Physical delivery of shares, ETF units, futures, or other underlyings.
- Early exercise decisions.
- Short assignment.
- Pin risk or random assignment around expiry.
- Exercise notices, OCC adjustments, corporate actions, or deliverable changes.
- Stock borrow, hard-to-borrow state, or short-stock positions created by assignment.
- Broker-specific portfolio margin, TIMS, SPAN, or real-time house margin engines.

`OptionExerciseStyle.American` and `OptionExerciseStyle.European` are instrument metadata today.
They validate option instruments, but they do not change expiry processing or create exercise
and assignment events.

## IBKR Mapping

`IBKRProFixedBroker` is an IBKR-style commission and financing profile. It should not be read
as an implementation of the full IBKR account model.

For an IBKR-sourced US equity-option backtest, the usual mapping is:

- Contract metadata maps to `option_instrument`: underlying, expiry, right, strike, multiplier,
  quote currency, and settlement currency.
- Quote rows map to `MarkUpdate` values for bid, ask, and last.
- Underlying reference prices map to `OptionUnderlyingUpdate`.
- Single-leg fills map to `fill_order!`; package fills map to `fill_option_strategy!`.
- Expiry and assignment do not map one-to-one. Fastback uses model-side cash intrinsic settlement,
  while many US equity and ETF options are American-style and physically settled.
- Margin should be treated as an internal model result. Reconcile it against broker statements
  before using it for broker-report matching or production risk limits.

## Practical Guidance

- Label SPY-like or AAPL-like option examples as cash-settled proxies.
- Close or roll positions before expiry when assignment, delivery, or dividend-sensitive exercise
  behavior matters to the research question.
- Do not interpret Fastback expiry trades as assigned stock trades.
- Treat expiry cashflows as model cashflows, not broker statement events.
- Use `check_invariants(acc)` in tests when adding option accounting, margin, expiry, or liquidation
  behavior.
