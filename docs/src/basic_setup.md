# Basic Backtest Setup

A backtest using Fastback typically consists of six main components. This guide walks you through each step to get you started with your first backtest.

## Overview

Fastback follows an event-driven architecture that mimics real-world trading systems. Each component plays a specific role in the backtesting process:

1. **Data**: Price and volume data for your instruments
2. **Account**: The central ledger for cash, positions, and trades
3. **Instruments**: Tradable assets with their specifications
4. **Data Collectors**: Tools for gathering performance metrics
5. **Trading Logic**: Your strategy implementation
6. **Analysis**: Examining results and performance

## 1. Data Preparation

Start by preparing your market data. Fastback is flexible about data sources - you can use DataFrames, CSV files, databases, or any iterable data structure.

```julia
using DataFrames, CSV

# Load data from CSV
data = CSV.read("price_data.csv", DataFrame)

# Or create synthetic data
dates = DateTime("2023-01-01"):Day(1):DateTime("2023-12-31")
prices = 100.0 .+ cumsum(0.1 .* randn(length(dates)))
data = DataFrame(date=dates, close=prices)
```

**Key considerations:**
- Ensure your data is sorted chronologically
- Include at minimum: timestamp and price data
- Additional columns like volume, bid/ask spreads enhance realism

## 2. Account Initialization

The [`Account`](@ref) is Fastback's central component that maintains all trading state.

```julia
using Fastback

# Create account with default settings
account = Account()

# Or customize with metadata types and timestamp precision
account = Account(
    odata=String,           # Order metadata type
    idata=NamedTuple,       # Instrument metadata type
    cdata=Nothing,          # Cash metadata type
    time_type=DateTime      # Timestamp type
)
```

**Next, fund your account:**

```julia
# Create and register cash asset
usd = Cash(:USD, digits=2)
register_cash_asset!(account, usd)

# Deposit initial capital
deposit!(account, usd, 100_000.0)

# Verify balance
println("Starting balance: ", cash_balance(account, usd))
```

## 3. Instrument Registration

Define the instruments you want to trade using the [`Instrument`](@ref) type.

```julia
# Create a stock instrument
aapl = Instrument(
    :AAPL,              # Symbol
    :USD,               # Quote currency
    base_digits=0,      # Base asset precision (shares)
    quote_digits=2,     # Quote currency precision (price)
    base_tick=1.0,      # Minimum quantity increment
    quote_tick=0.01     # Minimum price increment
)

# Register with account
register_instrument!(account, aapl)
```

**For multiple instruments:**

```julia
symbols = [:AAPL, :GOOGL, :MSFT]
instruments = [Instrument(sym, :USD, base_digits=0, quote_digits=2)
               for sym in symbols]

for inst in instruments
    register_instrument!(account, inst)
end
```

## 4. Data Collectors (Optional)

Set up collectors to track performance metrics throughout your backtest.

```julia
using Dates

# Track equity every hour
collect_equity, equity_data = periodic_collector(Float64, Hour(1))

# Track maximum drawdown
collect_drawdown, drawdown_data = drawdown_collector(
    DrawdownMode.Percentage,
    Hour(1)
)

# Track custom metrics when conditions are met
collect_trades, trade_count_data = predicate_collector(Int,
    (dt, value) -> value > 0  # Collect when trade count > 0
)
```

## 5. Trading Logic Implementation

Implement your strategy as a function that processes each data point and makes trading decisions.

```julia
function trading_strategy!(account, instruments, data_row)
    # Extract current market data
    current_time = data_row.date
    current_price = data_row.close

    # Example: Simple moving average crossover
    # (In practice, you'd calculate indicators from historical data)

    # Get current position
    inst = instruments[:AAPL]  # Assuming single instrument
    position = get_position(account, inst)

    # Trading logic
    if should_buy(data_row) && !has_exposure(position)
        # Create buy order
        quantity = 100.0  # Buy 100 shares
        order = Order(oid!(account), inst, current_time, current_price, quantity)

        # Execute order
        fill_order!(account, order, current_time, current_price; commission=1.0)

    elseif should_sell(data_row) && has_exposure(position)
        # Create sell order (close position)
        quantity = -position.quantity  # Sell all shares
        order = Order(oid!(account), inst, current_time, current_price, quantity)

        # Execute order
        fill_order!(account, order, current_time, current_price; commission=1.0)
    end

    # Update position P&L with current market price
    update_pnl!(account, inst, current_price, current_price)

    # Collect performance data
    current_equity = equity(account, usd)
    if should_collect(equity_data, current_time)
        collect_equity(current_time, current_equity)
    end
end

# Helper functions for strategy logic
function should_buy(data_row)
    # Implement your buy signal logic
    return data_row.close > 105.0  # Simple price threshold
end

function should_sell(data_row)
    # Implement your sell signal logic
    return data_row.close < 95.0   # Simple price threshold
end
```

## 6. Running the Backtest

Execute your backtest by iterating through your data:

```julia
# Run backtest
for row in eachrow(data)
    trading_strategy!(account, Dict(:AAPL => aapl), row)
end

println("Backtest completed!")
```

## 7. Analysis and Results

Examine your backtest results using Fastback's built-in analysis tools.

```julia
# Print account summary
println("=== Account Summary ===")
print_cash_balances(account)
print_equity_balances(account)
print_positions(account)

# Print trade history
println("\n=== Trade History ===")
print_trades(account; max_trades=10)  # Show last 10 trades

# Analyze collected data
println("\n=== Performance Metrics ===")
final_equity = values(equity_data)[end]
initial_equity = values(equity_data)[1]
total_return = (final_equity / initial_equity - 1) * 100

println("Total Return: $(round(total_return, digits=2))%")
println("Number of Trades: $(length(account.trades))")

# Export results for further analysis
using DataFrames
trades_df = DataFrame(trades_table(account))
equity_df = DataFrame(equity_data)
```

## Best Practices

### Performance Tips
- Pre-allocate data collectors with estimated capacity
- Use `@inbounds` in performance-critical loops when bounds checking is not needed
- Consider using more efficient timestamp types like `Timestamps64` for high-frequency data

### Strategy Development
- Start with simple strategies and gradually add complexity
- Validate your strategy logic with known market scenarios
- Consider transaction costs, slippage, and market impact
- Test edge cases like zero prices or missing data

### Error Handling
```julia
function safe_trading_strategy!(account, instruments, data_row)
    try
        trading_strategy!(account, instruments, data_row)
    catch e
        @warn "Error processing row at $(data_row.date): $e"
        # Continue backtest or handle appropriately
    end
end
```

## Next Steps

- Explore the [Examples](examples/gen/1_random_trading.md) for more sophisticated trading strategies
- Learn about multi-currency support in the examples
- Check out [Tables.jl Integration](integrations.md) for advanced data analysis
- Read the [API Reference](api.md) for detailed function documentation

Ready to build your first backtest? Check out the [Random Trading Example](examples/gen/1_random_trading.md) for a complete working example.
