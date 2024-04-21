# Development

## Testing

To run a subset of unit tests, call `Pkg.test` as follows, e.g. to run the tests in `test/utils.jl`:

```julia
import Pkg; Pkg.test("Fastback", test_args=["utils.jl"])
```

## TODOs

* Order placement price and quantity
* Execution price and quantity --> partial fills, slippage
* Fixed dollar-amount fee per trade
* Order placement date != execution date -> latency
* Incorporate funding cost info to positions, accrues over time
* Sequence number for orders and transactions

Principal Amount:
The total value of the position being financed.
Calculated as the number of contracts multiplied by the contract size and the price per contract.
