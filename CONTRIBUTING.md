# Contributing

Pull requests and issues are welcome.

## TODOs

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


For a backtesting engine like Fastback.jl, the most common missing built‑ins I see fall into three buckets: performance analytics, trading diagnostics, and
  operational/risk views. Here’s a concise list of useful plot types/illustrations/tables to consider as built‑in or extension modules.

  Performance analytics

  OK Cumulative equity curve with drawdown overlay (and max‑drawdown markers).
  - Drawdown “underwater” chart (depth and duration).
  - Rolling return windows (e.g., 1M/3M/1Y) and rolling volatility/Sharpe.
  - Monthly/quarterly returns heatmap + annual summary table.
  - Return distribution (histogram + KDE) with skew/kurtosis stats table.
  - Time‑to‑recovery distribution after drawdowns.

  Trading diagnostics

  - Trade P&L distribution (by trade, by day) and win/loss ratio chart.
  - Profit factor / expectancy plot (rolling and overall).
  - Holding‑period distribution (bars + quantiles).
  - MAE/MFE scatter for trades (quality of exits/entries).
  - Slippage vs volume/volatility scatter; cost attribution (spread, fees, impact).
  - Position size vs subsequent return (leverage efficiency).

  Risk & exposure

  OK Exposure over time (gross, net, long/short).
  - Exposure by asset/class/currency (stacked area).
  - Leverage and margin utilization time series + breach markers.
  - Concentration metrics (HHI) over time.
  - Correlation/covariance heatmaps and rolling correlations.
  - Tail‑risk plots (VaR/ES by horizon) + realized vs predicted.

  Execution & pipeline

  - Order lifecycle table (submitted/filled/canceled, latencies).
  - Fill ratio and partial‑fill analysis (histogram).
  - Queue position/latency scatter (if modeled).
  - Rejections by reason (bar chart).

  Portfolio attribution

  - P&L attribution by instrument/sector/currency.
  - Allocation change table (turnover by period).
  - Carry/roll/financing attribution if derivatives are supported.

  Statistical & validation

  - In‑sample vs out‑of‑sample equity curves on same chart.
  - Walk‑forward diagnostics table (performance by window).
  - Parameter sweep surface plots + robustness heatmaps.
  - Stability plots (performance vs small parameter perturbations).

  Tables that are especially useful

  - Summary performance metrics table (CAGR, vol, Sharpe, Sortino, max DD, MAR, Calmar, hit rate, profit factor).
  - Trade list table (entry/exit time, size, pnl, MAE/MFE, fees, slippage).
  - Exposure snapshot table (per currency/instrument).
  - Margin/account state timeline table (for audits).

  If you want, I can map these to Fastback’s data structures (Account/Position/Trade) and propose a minimal “analytics module” API that fits your current Tables.jl
  outputs and settlement/margin model.

  
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
