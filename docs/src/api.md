# API Reference

This page provides a comprehensive reference for all public functions, types, and constants in Fastback.jl.

## Core Types

```@docs
Account
Order
Trade
Position
Instrument
Cash
```

## Type Aliases

- **`Price`**: Type alias for `Float64`, used for prices and monetary values in quote currency
- **`Quantity`**: Type alias for `Float64`, used for position sizes and order quantities in base currency

## Account Management

### Cash Asset Management

```@docs
register_cash_asset!
deposit!
withdraw!
cash_balance
equity
```

### Instrument Management

```@docs
register_instrument!
get_position
```

### Trading Operations

```@docs
fill_order!
```

### Order Operations

```@docs
symbol(::Order)
trade_dir(::Order)
nominal_value(::Order)
```

### Trade Operations

```@docs
nominal_value(::Trade)
is_realizing
realized_return
```

### Position Analytics

```@docs
has_exposure
is_long
is_short
calc_pnl_local
calc_return_local
```

## Enumerations

### Trade Direction

The `TradeDir` enumeration represents trade directions:

- `TradeDir.Buy`: Buy/long direction
- `TradeDir.Sell`: Sell/short direction
- `TradeDir.Null`: No direction (zero quantity)

### Drawdown Mode

The `DrawdownMode` enumeration controls how drawdowns are calculated:

- `DrawdownMode.Absolute`: Absolute drawdown values
- `DrawdownMode.Percentage`: Percentage drawdown values

## Constants

### Type Aliases

- `Price`: Type alias for `Float64`, used for prices and monetary values
- `Quantity`: Type alias for `Float64`, used for position sizes and order quantities

## Examples

### Basic Account Setup

```julia
using Fastback

# Create account
account = Account()

# Create and register cash asset
usd = Cash(:USD, digits=2)
register_cash_asset!(account, usd)

# Deposit initial funds
deposit!(account, usd, 10000.0)

# Create and register instrument
aapl = Instrument(:AAPL, :USD, base_digits=0, quote_digits=2)
register_instrument!(account, aapl)
```

### Creating and Executing Orders

```julia
# Create an order
order = Order(oid!(account), aapl, DateTime("2023-01-01"), 150.0, 100.0)

# Execute the order
trade = fill_order!(account, order, DateTime("2023-01-01"), 150.50; commission=1.0)

# Check if trade realized P&L
is_realizing(trade)  # false for first trade (opening position)
```

### Working with Positions

```julia
# Get position for instrument
position = get_position(account, aapl)

# Check position exposure
has_exposure(position)  # true if position is open
is_long(position)      # true for long positions

# Calculate current P&L
current_pnl = calc_pnl_local(position, 155.0)  # P&L at price 155.0
```

### Data Collection

```julia
using Dates

# Set up equity collection every hour
collect_equity, equity_data = periodic_collector(Float64, Hour(1))

# Collect equity value
current_equity = equity(account, usd)
collect_equity(DateTime("2023-01-01T10:00:00"), current_equity)

# Access collected data
equity_values = values(equity_data)
equity_dates = dates(equity_data)
```