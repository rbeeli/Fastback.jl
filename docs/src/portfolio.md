# Target-weight portfolios

`Portfolio` is an optional, thin wrapper around an `Account`. It keeps no hidden
target or accounting state: explicit account operations remain available through
`portfolio.account`.

## Complete targets

`TargetWeights` represents a complete desired instrument set. Weights are signed,
need not sum to one, and are converted from base-currency fractions of pre-trade
equity. Cash is the residual. A zero-weight entry retains target membership, while
an open position omitted from the target is closed by default.

```julia
using Fastback
using Dates

acc = Account(;
    broker=NoOpBroker(),
    funding=AccountFunding.Margined,
    base_currency=CashSpec(:USD),
)
deposit!(acc, :USD, 10_000.0)

stock = register_instrument!(acc, spot_instrument(
    :ABCUSD, :ABC, :USD;
    base_tick=1.0,
    margin_init_long=0.5,
    margin_init_short=0.5,
    margin_maint_long=0.25,
    margin_maint_short=0.25,
))

dt = DateTime(2026, 1, 2)
update_marks!(acc, stock, dt, 99.0, 101.0, 100.0)

portfolio = Portfolio(acc)
target = TargetWeights(stock => 0.60)
result = rebalance!(portfolio, dt, target)

result.trades
portfolio_exposure(portfolio)
```

Sizing uses each instrument's `base_tick` and inward quantity bounds. Reversals
are split into a close and a reopen, and all reductions run before increases.
Set `RebalancePolicy(minimum_notional_base=...)` to suppress ordinary dust trades.
Full exits are never suppressed. Use
`RebalancePolicy(orphan_positions=OrphanPositionPolicy.Reject)` when an omitted
open position should reject planning instead of being closed.

## Fill models and funding

`TopOfBookFillModel` buys at the stored ask and sells at the stored bid.
`SpreadFillModel` can widen that observation by a minimum basis-point or tick
spread. Custom deterministic models can subtype `AbstractFillModel` and implement
`model_fill(model, context)`.

For fully funded accounts, planned sell reductions are credited first. Remaining
positive principal-exchange increases are uniformly scaled down, on tick, so they
fit the available settlement-currency cash. Negative target weights are rejected
under fully funded policy.

## Explicit contract rolls

Pass `RollTransition(front, next)` for compatible futures or perpetual contracts:

```julia
result = rebalance!(
    portfolio,
    dt,
    TargetWeights(next => 0.25);
    rolls=[RollTransition(front, next)],
)
```

Rolls execute before ordinary target adjustments. A failed opening leg leaves
the completed close in place and poisons the account. Roll graphs must be
acyclic, sources must be unique, and every destination must be present in the
complete target.

## Failure semantics

All market evidence, routes, targets, policies, and rolls are planned before the
first mutation. Once execution begins, successful earlier independent fills remain
committed if a later fill fails; callers can inspect the account and decide how to
recover. Target-weight rebalancing intentionally excludes options—use
`fill_option_strategy!` for option packages.
