# Contributing

Pull requests and issues are welcome.

## TODOs

- Account base currency != instrument currency
  - Add currency conversion rates
  - P&L in quote or base currency?
  - Fee currency?
- Fee model object
- Slippage model object
- Order sizer object
- Incorporate funding cost info to positions, accrues over time
- Backtesting portfolios (rebalancing, weights)
- More unit tests

## Testing

To run a specific file of unit tests, execute one of the following lines:

```julia
import Pkg; Pkg.test("Fastback", test_args=["utils.jl"])
import Pkg; Pkg.test("Fastback", test_args=["collectors.jl"])
import Pkg; Pkg.test("Fastback", test_args=["batch_backtest.jl"])
import Pkg; Pkg.test("Fastback", test_args=["position.jl"])
import Pkg; Pkg.test("Fastback", test_args=["account.jl"])
```

## Building documentation

The documentation is built using [Documenter.jl](https://documenter.juliadocs.org/stable/).

To rebuild, run the following command from the root of the repository:

```bash
cd docs
julia --project make.jl
```

To view the documentation locally, run:

```bash
cd docs
npx live-server ./build
```
