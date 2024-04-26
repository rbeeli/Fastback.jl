# Fastback basic backtest setup

A backtest using Fastback usually consists of the following parts:

1. **Data**: The data you want to backtest on. This can be a DataFrame, a CSV file, or a database. Ideally, it can be looped over efficiently.

2. **Instruments**: The instruments you want to trade with, e.g. stocks or cryptocurrencies.

3. **Account**: The account you want to backtest with. This includes the initial capital and all instruments. Positions, trades and general bookkeeping is done here.

4. **Data collectors**: Initialize collectors for account balance, equity, drawdowns, etc. These optional data collectors can be used to analyze the backtest results.

5. **Trading logic**: The trading strategy you want to backtest. It is called at every iteration of the input data and takes trading decisions like buying or selling stocks.

6. **Analysis**: Analyze the backtest results, e.g. the account balance, equity, drawdowns, etc. by e.g. printing to console or displaying plots. Alternatively, store the results in a Vector or DataFrame for further analysis, i.e. when running an optimization to find the best strategy parameters.