# Execution and errors

Execution behavior (user-facing):

- `fill_order!` records a `Trade` when the fill is accepted.
- When a fill is rejected, `fill_order!` throws `OrderRejectError`.
- `settle_expiry!`, `process_expiries!`, `liquidate_all!`, and `liquidate_to_maintenance!` send close-only synthetic fills (`fill_qty = -position_qty`) with `allow_inactive=true`, so they do not reject on incremental margin checks (`inc_qty == 0`).
- Those helpers can still throw non-rejection errors (for example non-finite settlement marks or liquidation loop limits).

```@example
using Fastback, Dates

acc = Account(;
    broker=FlatFeeBroker(pct=0.001),
    base_currency=CashSpec(:USD),
)
deposit!(acc, :USD, 100.0)
inst = register_instrument!(acc, spot_instrument(:ABC, :ABC, :USD))

order = Order(oid!(acc), inst, DateTime(2024, 1, 2), 200.0, 1.0)

try
    fill_order!(acc, order; dt=order.date, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)
catch err
    err isa OrderRejectError ? string("rejected: ", err.reason) : rethrow()
end
```
