"""
    Cash{CData}

Represents a cash asset (currency) that can be held in an account.

A cash asset defines a liquid currency or asset that can be used for trading
and as a settlement currency for instruments. Cash assets must be registered
with an account before they can be used for deposits, withdrawals, or trading.

# Type Parameters
- `CData`: Type for custom cash asset metadata (can be `Nothing` if unused)

# Fields
- `index::UInt`: Unique cash asset index for fast lookup (set automatically)
- `symbol::Symbol`: Currency symbol (e.g., :USD, :EUR, :BTC)
- `digits::Int`: Number of decimal places for display formatting
- `data::CData`: Optional custom metadata

# Examples
```julia
# Create basic cash assets
usd = Cash(:USD, digits=2)         # US Dollar with cent precision
btc = Cash(:BTC, digits=8)         # Bitcoin with satoshi precision
eur = Cash(:EUR, digits=2)         # Euro with cent precision

# With custom metadata
usd_meta = Cash(:USD, digits=2,
                data=(country="US", central_bank="FED"))

# Register with account before use
register_cash_asset!(account, usd)
deposit!(account, usd, 10000.0)
```

See also: [`register_cash_asset!`](@ref), [`deposit!`](@ref), [`withdraw!`](@ref)
"""
mutable struct Cash{CData}
    index::UInt               # unique index starting from 1 (used for array indexing and hashing)
    const symbol::Symbol
    const digits::Int
    const data::CData

    function Cash(
        symbol::Symbol
        ;
        digits=2,
        data::CData=nothing
    ) where {CData}
        new{CData}(
            0, # index
            symbol,
            digits,
            data
        )
    end
end

@inline Base.hash(cash::Cash) = cash.index  # custom hash for better performance

@inline function format_cash(cash::Cash, value)
    Printf.format(Printf.Format("%.$(cash.digits)f"), value)
end

function Base.show(io::IO, cash::Cash)
    print(io, "[Cash] " *
              "index=$(cash.index) " *
              "symbol=$(cash.symbol) " *
              "digits=$(cash.digits)")
end
