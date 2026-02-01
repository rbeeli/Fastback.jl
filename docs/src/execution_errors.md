# Execution and errors

Execution behavior (user-facing):

- `fill_order!` records a `Trade` when the fill is accepted.
- When a fill is rejected, `fill_order!` throws `OrderRejectError`.
- The same error can bubble up from expiry settlement or liquidation helpers.

```@example
using Fastback, Dates

acc = Account(; base_currency=:USD)
deposit!(acc, Cash(:USD), 100.0)
inst = register_instrument!(acc, spot_instrument(:ABC, :ABC, :USD))

order = Order(oid!(acc), inst, DateTime(2024, 1, 2), 200.0, 1.0)

try
    fill_order!(acc, order; dt=order.date, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)
catch err
    err isa OrderRejectError ? string("rejected: ", err.reason) : rethrow()
end
```
