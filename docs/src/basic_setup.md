# Fastback basic backtest setup

A backtest using Fastback usually consists of the following parts:

### 1. Data

Acquire data like price, volume and other features you want to backtest on.
This can be from a `DataFrame`, a CSV file, or a database.
Ideally, it can be looped over or streamed efficiently.

### 2. Account

Initialize the account you want to backtest with.
The account holds the assets (funds), positions, trades, and does all the bookkeeping.
Create `Account` first, then register additional cash assets on the account:

```julia
er = ExchangeRates()
account = Account(;
    broker=FlatFeeBroker(pct=0.001),
    funding=AccountFunding.Margined,
    base_currency=CashSpec(:USD),
    exchange_rates=er,
)
usd = cash_asset(account, :USD)
eur = register_cash_asset!(account, CashSpec(:EUR; digits=2)) # optional
```

Fund the account with `deposit!(account, usd, amount)`.
For non-base currencies, use their registered `Cash` handles, e.g. `deposit!(account, eur, amount)`.
Use `withdraw!(account, usd, amount)` later when simulating outflows.

### 3. Instruments

Register the instruments you want to trade with, e.g. stocks or cryptocurrencies.
Instruments specify the display symbol, base- and quote symbols, tick sizes and valid value ranges.

### 4. Data collectors

Initialize data collectors for account balance, equity, drawdowns, etc.
Data collectors are not required, but help in collecting data for further analysis of the backtest results.

### 5. Trading logic

Implement the actual trading logic you want to backtest, i.e. the strategy.
It is called at every iteration of the input data and takes trading decisions like buying or selling instruments.
In a live-setting, the data would be streamed to the trading logic instead of being looped over.

### 6. Analysis

Analyze the backtest results by inspecting the account and the collected data.
Print account balances, equity, drawdowns, etc., or create plots.
Alternatively, store the results in a `Vector` or `DataFrame` for further analysis.
For example, when running an optimization, we compute the metric of interest and store it in a `Vector` or similar.
At the end of the optimization, we can then inspect the results and find the best parameters.

For a runnable minimal example, see the [Getting started](getting_started.md) page.
