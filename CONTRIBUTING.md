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
- Margin trading
  - Incorporate funding cost info to positions, accrues over time
- Backtesting portfolios (rebalancing, weights)
- More unit tests

@inline format_base(acc::Account, value) = Format.format(value; precision=acc.base_asset.digits, commas=true)

"""
Returns the balance of the given asset in the account in the account base currency.

This does not include the value of open positions.
"""
@inline function get_asset_value_base(acc::Account, asset::Asset)
    get_rate(acc.exchange_rates, asset, acc.base_asset) * get_asset_value(acc, asset)
end

"""
Computes the total account equity in the base currency.

Equity is your balance +/- the floating profit/loss of your open positions,
not including closing fees.
"""
@inline function total_equity(acc::Account)
    total = 0.0
    for asset in acc.assets
        er = get_rate(acc.exchange_rates, asset, acc.base_asset)
        total += er * @inbounds acc.equities[asset.index]
    end
    total
end



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
julia --project --eval 'using Pkg; Pkg.resolve(); Pkg.instantiate()'
julia --project make.jl
```

To view the documentation locally, run:

```bash
cd docs
npx live-server ./build
```
