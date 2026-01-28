# Contributing

Pull requests and issues are welcome.

## TODOs

- Medium: Borrow-fee accrual shares a single acc.last_borrow_fee_dt across all positions. If a new short is opened after the last accrual (or a short is closed mid-interval), the next accrue_borrow_fees! call charges that position for the entire elapsed period (or misses part of it). Accurate fees therefore depend on the caller manually invoking accrual at every position change. Consider tracking a per-position last-accrual timestamp or automatically “closing” the accrual window inside fill handling so fee periods align with actual exposure. (src/borrow_fees.jl:15-41)

- Low: Interest accrual uses the same account-level timestamping pattern; balances are assumed constant between accrue_interest! calls. Deposits/withdrawals or cashflows between accrual points will be treated as if they were present for the whole interval, biasing interest earned/paid unless accrual is called immediately before each balance change. If that’s unintended, mirror the fix above or document the required call pattern. (src/interest.jl:35-56)

- FX robustness for research-grade multi-currency margining (optional but high leverage)

    Right now SpotExchangeRates requires a direct rate for every required conversion pair. For research this gets annoying fast.

    Option A (minimal): enforce “rates-to-base must exist”

    Add a helper require_base_fx!(acc) that checks every cash asset with nonzero balance/equity/margin has a direct rate to base.

    Call it inside:

    equity_base_ccy

    *_margin_used_base_ccy

    check_fill_constraints (BaseCurrency path)

    Option B (better UX): triangulate rates via graph

    Implement GraphExchangeRates <: ExchangeRates

    Store directed edges updated by user

    Cache full NxN matrix after each update via BFS/DFS from each node (N is small)

    get_rate uses cached matrix, so conversions stay fast

    Tests

    Build rates EUR→USD and USD→CHF, verify EUR→CHF works without explicit update.

    Verify base conversions and to_settle conversions work when only a connected graph exists.

    Verification

    Users stop fighting FX plumbing.

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
