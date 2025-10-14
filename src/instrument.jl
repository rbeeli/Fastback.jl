using Printf

"""
    Instrument{IData}

Represents a tradable financial instrument with its specifications and constraints.

An instrument defines a tradable asset by specifying the base and quote currencies,
tick sizes, quantity limits, and display formatting. It serves as the contract
specification for all trading operations.

# Type Parameters
- `IData`: Type for custom instrument metadata (can be `Nothing` if unused)

# Fields
- `index::UInt`: Unique instrument index for fast lookup (set automatically)
- `symbol::Symbol`: Display symbol for the instrument (e.g., :BTCUSD)
- `base_symbol::Symbol`: Symbol of the base asset being traded (e.g., :BTC)
- `base_tick::Quantity`: Minimum quantity increment for orders
- `base_min::Quantity`: Minimum allowed quantity (can be -Inf for short selling)
- `base_max::Quantity`: Maximum allowed quantity
- `base_digits::Int`: Decimal places for displaying quantities
- `quote_symbol::Symbol`: Symbol of the quote currency (e.g., :USD)
- `quote_tick::Price`: Minimum price increment
- `quote_digits::Int`: Decimal places for displaying prices
- `metadata::IData`: Optional custom metadata

# Examples
```julia
# Create a stock instrument
aapl = Instrument(:AAPL, :AAPL, :USD,
                  base_digits=0,      # Whole shares
                  quote_digits=2,     # Cent precision
                  base_tick=1.0,      # 1 share minimum
                  quote_tick=0.01)    # 1 cent minimum

# Create a cryptocurrency instrument
btc = Instrument(:BTCUSD, :BTC, :USD,
                 base_digits=8,       # Satoshi precision
                 quote_digits=2,      # Dollar precision
                 base_tick=0.00000001,
                 quote_tick=0.01)

# With custom metadata
inst = Instrument(:CUSTOM, :BASE, :USD,
                  metadata=(sector="Tech", exchange="NASDAQ"))
```

See also: [`register_instrument!`](@ref), [`Account`](@ref)
"""
mutable struct Instrument{IData}
    index::UInt                   # unique index for each instrument starting from 1 (used for array indexing and hashing)
    const symbol::Symbol

    const base_symbol::Symbol
    const base_tick::Quantity     # minimum price increment of base asset
    const base_min::Quantity      # minimum quantity of base asset
    const base_max::Quantity      # maximum quantity of base asset
    const base_digits::Int        # number of digits after the decimal point for display

    const quote_symbol::Symbol
    const quote_tick::Price       # minimum price increment of base asset
    const quote_digits::Int       # number of digits after the decimal point for display

    const metadata::IData

    function Instrument(
        symbol::Symbol,
        base_symbol::Symbol,
        quote_symbol::Symbol
        ;
        base_tick::Quantity=0.01,
        base_min::Quantity=-Inf,
        base_max::Quantity=Inf,
        base_digits=2,
        quote_tick::Price=0.01,
        quote_digits=2,
        metadata::IData=nothing
    ) where {IData}
        new{IData}(
            0, # index
            symbol,
            base_symbol,
            base_tick,
            base_min,
            base_max,
            base_digits,
            quote_symbol,
            quote_tick,
            quote_digits,
            metadata
        )
    end
end

# Convenience constructor that infers symbol from base and quote
function Instrument(
    base_symbol::Symbol,
    quote_symbol::Symbol;
    kwargs...
)
    symbol = Symbol(string(base_symbol) * "/" * string(quote_symbol))
    Instrument(symbol, base_symbol, quote_symbol; kwargs...)
end

@inline Base.hash(inst::Instrument) = inst.index  # custom hash for better performance

@inline format_base(inst::Instrument, value) = Printf.format(Printf.Format("%.$(inst.base_digits)f"), value)
@inline format_quote(inst::Instrument, value) = Printf.format(Printf.Format("%.$(inst.quote_digits)f"), value)

function Base.show(io::IO, inst::Instrument{IData}) where {IData}
    str = "[Instrument] " *
          "symbol=$(inst.symbol) " *
          "base=$(inst.base_symbol) [$(format_base(inst, inst.base_min)), $(format_base(inst, inst.base_max))]±$(format_base(inst, inst.base_tick)) " *
          "quote=$(inst.quote_symbol)±$(format_quote(inst, inst.quote_tick))"
    if IData !== nothing
        str *= " metadata=$(inst.metadata)"
    end
    print(io, str)
end
