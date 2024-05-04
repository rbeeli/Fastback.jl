# Fastback basic backtest setup

A backtest using Fastback usually consists of the following parts:

### 1. Data

Acquire data like price, volume and other featuers you want to backtest on.
This can be from a `DataFrame`, a CSV file, or a database.
Ideally, it can be looped over efficiently.

### 2. Account

Initialize the account you want to backtest with.
The account holds the assets (funds), positions, trades, and does all the bookkeeping.
Specify the initial funds for the account used for trading instruments. For multi-currency backtesting, an exchange rate provider can be specified to convert asset currency to account base currency, see `Account` named parameter `exchange_rates` (the default implementation always returns `1.0`).

### 3. Instruments

The instruments you want to trade with, e.g. stocks or cryptocurrencies.
Instruments specify the display symbol, base- and quote assets, tick sizes and value ranges.

### 4. Data collectors

Initialize collectors for account balance, equity, drawdowns, etc.
Data collectors are not required, but help in collecting data for further analysis of the backtest results.

### 5. Trading logic

The actual trading logic you want to backtest.
It is called at every iteration of the input data and takes trading decisions like buying or selling stocks. In a live-setting, the data would be streamed to the trading logic instead of being looped over.

### 6. Analysis

Analyze the backtest results.
Print account balances, equity, drawdowns, etc. or create plots. Alternatively, store the results in a `Vector` or `DataFrame` for further analysis, for example when running an optimization to find the best strategy parameters.
