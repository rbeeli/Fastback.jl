# Execution and errors

Execution behavior (user-facing):

- `fill_order!` records a `Trade` when the fill is accepted.
- `create_order!` validates the account-owned instrument, price, quantity, and timestamp, assigns the order ID, and advances account time.
- When a fill is rejected, `fill_order!` throws `OrderRejectError`.
- `settle_expiry!`, `process_expiries!`, `liquidate_all!`, and `liquidate_to_maintenance!` use internal close-only settlement/liquidation paths, so they do not expose normal order lifecycle bypass flags on `fill_order!`.
- Those helpers can still throw non-rejection errors (for example stale/non-finite stored quote state or liquidation loop limits).

```@example
using Fastback, Dates

acc = Account(;
    broker=FlatFeeBroker(pct=0.001),
    base_currency=CashSpec(:USD),
)
deposit!(acc, :USD, 100.0)
inst = register_instrument!(acc, spot_instrument(:ABC, :ABC, :USD))

order = create_order!(acc, inst, DateTime(2024, 1, 2), 200.0, 1.0)

try
    fill_order!(acc, order; dt=order.date, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)
catch err
    err isa OrderRejectError ? string("rejected: ", err.reason) : rethrow()
end
```

Creating a valid order is an observable account-time transition even when its
later fill is rejected. Direct `Order(id, ...)` construction remains available
for low-level compatibility, but does not update account state.
