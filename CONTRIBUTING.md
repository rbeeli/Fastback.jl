# Contributing

Pull requests and issues are welcome.

## TODOs

- Incorporate funding cost info to positions, accrues over time
- Make price and quantity types configurable
- Logging of events
- Unit tests

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
cd docs && julia --project=. make.jl && cd ..
```
