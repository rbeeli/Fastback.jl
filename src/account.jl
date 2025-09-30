"""
    Account{TTime,OData,IData,CData}

Central ledger that maintains all trading account state and bookkeeping.

The Account is Fastback's central component that tracks cash balances, open positions,
executed trades, and provides the foundation for all trading operations. It supports
multi-currency trading and maintains detailed records of all transactions.

# Type Parameters
- `TTime<:Dates.AbstractTime`: The time type used for timestamps
- `OData`: Type for custom order metadata (can be `Nothing` if unused)
- `IData`: Type for custom instrument metadata (can be `Nothing` if unused)
- `CData`: Type for custom cash asset metadata (can be `Nothing` if unused)

# Fields
- `cash::Vector{Cash{CData}}`: Registered cash assets (currencies)
- `cash_by_symbol::Dict{Symbol,Cash{CData}}`: Fast lookup of cash assets by symbol
- `balances::Vector{Price}`: Cash balance for each registered currency
- `equities::Vector{Price}`: Total equity (balance + unrealized P&L) for each currency
- `positions::Vector{Position{TTime,OData,IData}}`: Open positions for all instruments
- `trades::Vector{Trade{TTime,OData,IData}}`: Historical record of all executed trades
- `order_sequence::Int`: Counter for generating unique order IDs
- `trade_sequence::Int`: Counter for generating unique trade IDs
- `date_format::Dates.DateFormat`: Format for displaying timestamps

# Examples
```julia
# Create a basic account
account = Account()

# Create an account with custom metadata types
account = Account(odata=String, idata=NamedTuple, cdata=Nothing)

# Create an account with nanosecond timestamps
account = Account(time_type=NanoDate)
```

See also: [`register_cash_asset!`](@ref), [`deposit!`](@ref), [`register_instrument!`](@ref), [`fill_order!`](@ref)
"""
mutable struct Account{TTime<:Dates.AbstractTime,OData,IData,CData}
    const cash::Vector{Cash{CData}}
    const cash_by_symbol::Dict{Symbol,Cash{CData}}
    const balances::Vector{Price}           # balance per cash currency
    const equities::Vector{Price}           # equity per cash currency
    const positions::Vector{Position{TTime,OData,IData}}
    const trades::Vector{Trade{TTime,OData,IData}}
    order_sequence::Int
    trade_sequence::Int
    const date_format::Dates.DateFormat

    function Account(
        ;
        date_format=dateformat"yyyy-mm-dd HH:MM:SS",
        order_sequence=0,
        trade_sequence=0,
        odata::Type{OData}=Nothing,
        idata::Type{IData}=Nothing,
        cdata::Type{CData}=Nothing,
        time_type::Type{TTime}=DateTime,
    ) where {TTime<:Dates.AbstractTime,OData,IData,CData}
        new{TTime,OData,IData,CData}(
            Vector{Cash{CData}}(), # cash
            Dict{Symbol,Cash{CData}}(), # cash_by_symbol
            Vector{Price}(), # balances
            Vector{Price}(), # equities
            Vector{Position{TTime,OData,IData}}(), # positions
            Vector{Trade{TTime,OData,IData}}(), # trades
            order_sequence,
            trade_sequence,
            date_format
        )
    end
end

@inline format_datetime(acc::Account, x) = Dates.format(x, acc.date_format)
@inline oid!(acc::Account) = acc.order_sequence += 1
@inline tid!(acc::Account) = acc.trade_sequence += 1

"""
Returns a `Cash` object with the given symbol.

Cash objects must be registered first in the account before
they can be accessed, see `register_cash_asset!`.
"""
@inline cash_asset(acc::Account, symbol::Symbol) = @inbounds acc.cash_by_symbol[symbol]

"""
    has_cash_asset(account::Account, symbol::Symbol) -> Bool

Check if a cash asset with the given symbol is registered in the account.

Returns `true` if the cash asset is already registered, `false` otherwise.
Cash assets must be registered before they can be used for deposits, withdrawals,
or as quote currencies for instruments.

# Arguments
- `account::Account`: The account to check
- `symbol::Symbol`: The symbol of the cash asset to look for

# Returns
- `Bool`: `true` if the cash asset is registered, `false` otherwise

# Examples
```julia
account = Account()
usd = Cash(:USD, digits=2)

has_cash_asset(account, :USD)  # Returns false (not registered yet)

register_cash_asset!(account, usd)
has_cash_asset(account, :USD)  # Returns true (now registered)
```

See also: `register_cash_asset!`, `cash_asset`, `Cash`
"""
@inline has_cash_asset(acc::Account, symbol::Symbol) = haskey(acc.cash_by_symbol, symbol)

"""
    register_cash_asset!(account::Account, cash::Cash) -> Nothing

Register a new cash asset (currency) with the account.

Cash assets must be registered before they can be used for deposits, withdrawals, or as
quote currencies for instruments. This function initializes the cash asset's index and
creates entries in the account's balance and equity tracking arrays.

# Arguments
- `account::Account`: The account to register the cash asset with
- `cash::Cash`: The cash asset to register

# Throws
- `ArgumentError`: If a cash asset with the same symbol is already registered

# Examples
```julia
# Create and register cash assets
account = Account()
usd = Cash(:USD, digits=2)
eur = Cash(:EUR, digits=2)

register_cash_asset!(account, usd)
register_cash_asset!(account, eur)

# Check if registered
has_cash_asset(account, :USD)  # Returns true
```

See also: `Cash`, `has_cash_asset`, `deposit!`, `withdraw!`
"""
function register_cash_asset!(
    acc::Account{TTime,OData,IData,CData},
    cash::Cash{CData}
) where {TTime<:Dates.AbstractTime,OData,IData,CData}
    !has_cash_asset(acc, cash.symbol) || throw(ArgumentError("Cash with symbol '$(cash.symbol)' already registered."))

    # set index for fast array indexing and hashing
    cash.index = length(acc.cash) + 1

    push!(acc.cash, cash)
    acc.cash_by_symbol[cash.symbol] = cash
    push!(acc.balances, zero(Price))
    push!(acc.equities, zero(Price))
end

@inline function _adjust_cash!(
    acc::Account{TTime,OData,IData,CData},
    cash::Cash{CData},
    amount::Real
) where {TTime<:Dates.AbstractTime,OData,IData,CData}
    # register cash object if not already registered
    has_cash_asset(acc, cash.symbol) || register_cash_asset!(acc, cash)

    # ensure cash object was registered
    cash.index > 0 || throw(ArgumentError("Cash with symbol '$(cash.symbol)' not registered."))

    # update balance and equity for the asset
    @inbounds begin
        acc.balances[cash.index] += Price(amount)
        acc.equities[cash.index] += Price(amount)
    end

    cash
end

"""
    deposit!(account::Account, cash::Cash, amount::Real) -> Cash

Deposit funds into the account for a specific cash asset.

Adds the specified amount to both the cash balance and equity for the given currency.
If the cash asset is not yet registered with the account, it will be registered automatically.

# Arguments
- `account::Account`: The account to deposit funds into
- `cash::Cash`: The cash asset (currency) to deposit
- `amount::Real`: The amount to deposit (must be non-negative)

# Returns
- `Cash`: The cash asset that received the deposit

# Throws
- `ArgumentError`: If the deposit amount is negative

# Examples
```julia
# Create account and cash asset
account = Account()
usd = Cash(:USD, digits=2)

# Deposit initial funds
deposit!(account, usd, 10000.0)

# Check balance
cash_balance(account, usd)  # Returns 10000.0
```

See also: [`withdraw!`](@ref), [`cash_balance`](@ref), [`register_cash_asset!`](@ref)
"""
function deposit!(
    acc::Account{TTime,OData,IData,CData},
    cash::Cash{CData},
    amount::Real
) where {TTime<:Dates.AbstractTime,OData,IData,CData}
    isless(amount, zero(amount)) && throw(ArgumentError("Deposit amount must be non-negative."))
    _adjust_cash!(acc, cash, amount)
end

"""
    withdraw!(account::Account, cash::Cash, amount::Real) -> Cash

Withdraw funds from the account for a specific cash asset.

Subtracts the specified amount from both the cash balance and equity for the given currency.
This function can result in negative balances if the withdrawal exceeds available funds.

# Arguments
- `account::Account`: The account to withdraw funds from
- `cash::Cash`: The cash asset (currency) to withdraw from
- `amount::Real`: The amount to withdraw (must be non-negative)

# Returns
- `Cash`: The cash asset that had funds withdrawn

# Throws
- `ArgumentError`: If the withdrawal amount is negative

# Examples
```julia
# Withdraw funds
withdraw!(account, usd, 1000.0)

# Check remaining balance
cash_balance(account, usd)  # Returns previous balance - 1000.0
```

See also: `deposit!`, `cash_balance`
"""
function withdraw!(
    acc::Account{TTime,OData,IData,CData},
    cash::Cash{CData},
    amount::Real
) where {TTime<:Dates.AbstractTime,OData,IData,CData}
    isless(amount, zero(amount)) && throw(ArgumentError("Withdraw amount must be non-negative."))
    _adjust_cash!(acc, cash, -amount)
end

"""
    register_instrument!(account::Account, instrument::Instrument) -> Instrument

Register a new trading instrument with the account.

Instruments must be registered before they can be traded. This function creates a position
entry for the instrument and assigns it a unique index for fast lookup. Each instrument
can only be registered once per account.

# Arguments
- `account::Account`: The account to register the instrument with
- `instrument::Instrument`: The trading instrument to register

# Returns
- `Instrument`: The registered instrument (same as input)

# Throws
- `ArgumentError`: If an instrument with the same symbol is already registered

# Examples
```julia
# Create and register instruments
account = Account()
usd = Cash(:USD, digits=2)
register_cash_asset!(account, usd)

# Register a stock
aapl = Instrument(:AAPL, :USD, base_digits=0, quote_digits=2)
register_instrument!(account, aapl)

# Register a cryptocurrency
btc = Instrument(:BTCUSD, :BTC, :USD, base_digits=8, quote_digits=2)
register_instrument!(account, btc)

# Check position (will be empty initially)
position = get_position(account, aapl)
has_exposure(position)  # Returns false (no trades yet)
```

See also: [`Instrument`](@ref), [`get_position`](@ref), [`Position`](@ref)
"""
function register_instrument!(
    acc::Account{TTime,OData,IData,CData},
    inst::Instrument{IData}
) where {TTime<:Dates.AbstractTime,OData,IData,CData}
    if any(x -> x.inst.symbol == inst.symbol, acc.positions)
        throw(ArgumentError("Instrument $(inst.symbol) already registered"))
    end

    # set asset index for fast array indexing and hashing
    inst.index = length(acc.positions) + 1

    push!(acc.positions, Position{TTime,OData}(inst.index, inst))

    inst
end

"""
    get_position(account::Account, instrument::Instrument) -> Position

Get the position object for a specific instrument in the account.

Returns the position that tracks the net exposure, average price, and P&L
for the given instrument. The position is created automatically when an
instrument is registered with the account.

# Arguments
- `account::Account`: The account to query
- `instrument::Instrument`: The instrument to get the position for

# Returns
- `Position`: The position object for the instrument

# Examples
```julia
# Register instrument and get its position
aapl = Instrument(:AAPL, :USD, base_digits=0, quote_digits=2)
register_instrument!(account, aapl)

position = get_position(account, aapl)

# Check position state
has_exposure(position)     # false initially (no trades)
position.quantity          # 0.0 (no shares)
position.avg_price         # 0.0 (no average price yet)

# After trading
order = Order(oid!(account), aapl, DateTime("2023-01-01"), 100.0, 10.0)
fill_order!(account, order, DateTime("2023-01-01"), 100.0)

has_exposure(position)     # true (now has 10 shares)
position.quantity          # 10.0
position.avg_price         # 100.0
```

See also: [`Position`](@ref), [`register_instrument!`](@ref), [`has_exposure`](@ref)
"""
@inline function get_position(acc::Account, inst::Instrument)
    @inbounds acc.positions[inst.index]
end

"""
Determines if the account has non-zero exposure to the given instrument.
"""
@inline function is_exposed_to(acc::Account, inst::Instrument)
    has_exposure(get_position(acc, inst))
end

"""
Determines if the account has non-zero exposure to the given instrument
in the given direction (`Buy`, `Sell`).
"""
@inline function is_exposed_to(acc::Account, inst::Instrument, dir::TradeDir.T)
    sign(trade_dir(get_position(acc, inst))) == sign(dir)
end

"""
    cash_balance(account::Account, cash::Cash) -> Price
    cash_balance(account::Account, cash_symbol::Symbol) -> Price

Get the cash balance for a specific currency in the account.

Returns the available cash balance excluding unrealized P&L from open positions.
For total value including unrealized P&L, use [`equity`](@ref) instead.

# Arguments
- `account::Account`: The account to query
- `cash::Cash` or `cash_symbol::Symbol`: The cash asset or its symbol

# Returns
- `Price`: The cash balance in the specified currency

# Examples
```julia
# Check USD balance
usd_balance = cash_balance(account, usd)          # Using Cash object
usd_balance = cash_balance(account, :USD)         # Using symbol

# After deposits and trades
deposit!(account, usd, 10000.0)
println("Cash: ", cash_balance(account, :USD))    # Shows deposited amount
println("Equity: ", equity(account, :USD))        # Includes unrealized P&L
```

See also: `equity`, `deposit!`, `withdraw!`
"""
@inline cash_balance(acc::Account, cash::Cash) = @inbounds acc.balances[cash.index]
@inline cash_balance(acc::Account, cash_symbol::Symbol) = cash_balance(acc, cash_asset(acc, cash_symbol))

"""
    equity(account::Account, cash::Cash) -> Price
    equity(account::Account, cash_symbol::Symbol) -> Price

Get the total equity value for a specific currency in the account.

Equity represents the total value including both cash balance and unrealized P&L
from open positions denominated in the specified currency. This gives the current
total value of holdings in that currency.

**Formula**: `Equity = Cash Balance + Unrealized P&L`

# Arguments
- `account::Account`: The account to query
- `cash::Cash` or `cash_symbol::Symbol`: The cash asset or its symbol

# Returns
- `Price`: The total equity value in the specified currency

# Examples
```julia
# Compare cash balance vs equity
cash_balance(account, :USD)  # 10000.0 (original deposit)
equity(account, :USD)        # 10150.0 (includes +150 unrealized P&L)

# After closing positions, equity equals cash balance
println("Cash: ", cash_balance(account, usd))
println("Equity: ", equity(account, usd))  # Same as cash after P&L is realized
```

See also: `cash_balance`, `update_pnl!`, `Position`
"""
@inline equity(acc::Account, cash::Cash) = @inbounds acc.equities[cash.index]
@inline equity(acc::Account, cash_symbol::Symbol) = equity(acc, cash_asset(acc, cash_symbol))
