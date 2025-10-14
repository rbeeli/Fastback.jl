using Dates

"""
    Order{TTime,OData,IData}

Represents a trading order with all necessary execution parameters.

An order encapsulates an instruction to trade an instrument at a specific time, price, and quantity,
with optional take-profit and stop-loss levels and custom metadata.

# Type Parameters
- `TTime<:Dates.AbstractTime`: The time type used for timestamps
- `OData`: Type for custom order metadata (can be `Nothing` if unused)
- `IData`: Type for custom instrument metadata

# Fields
- `oid::Int`: Unique order identifier
- `inst::Instrument{IData}`: The instrument to trade
- `date::TTime`: Order timestamp
- `price::Price`: Order price in quote currency
- `quantity::Quantity`: Order quantity in base currency (negative for short selling)
- `take_profit::Price`: Optional take-profit price (NaN if not set)
- `stop_loss::Price`: Optional stop-loss price (NaN if not set)
- `metadata::OData`: Optional custom order metadata

# Examples
```julia
# Create a simple buy order
order = Order(1, instrument, DateTime("2023-01-01"), 100.0, 10.0)

# Create an order with take-profit and stop-loss
order = Order(2, instrument, DateTime("2023-01-01"), 100.0, 10.0;
              take_profit=110.0, stop_loss=95.0)

# Create an order with custom metadata
order = Order(3, instrument, DateTime("2023-01-01"), 100.0, 10.0;
              metadata="signal_strength_0.8")
```

See also: [`Trade`](@ref), [`fill_order!`](@ref), [`Instrument`](@ref)
"""
mutable struct Order{TTime<:Dates.AbstractTime,OData,IData}
    const oid::Int
    const inst::Instrument{IData}
    const date::TTime
    const price::Price
    const quantity::Quantity   # negative = short selling
    take_profit::Price
    stop_loss::Price
    metadata::OData

    function Order(
        oid,
        inst::Instrument{IData},
        date::TTime,
        price::Price,
        quantity::Quantity
        ;
        take_profit::Price=Price(NaN),
        stop_loss::Price=Price(NaN),
        metadata::OData=nothing
    ) where {TTime<:Dates.AbstractTime,OData,IData}
        new{TTime,OData,IData}(
            oid,
            inst,
            date,
            price,
            quantity,
            take_profit,
            stop_loss,
            metadata,
        )
    end
end

"""
    symbol(order::Order) -> Symbol

Get the symbol of the instrument associated with this order.

# Arguments
- `order::Order`: The order to get the symbol from

# Returns
- `Symbol`: The instrument symbol

# Examples
```julia
order = Order(1, instrument, DateTime("2023-01-01"), 100.0, 10.0)
symbol(order)  # Returns the instrument's symbol, e.g., :AAPL
```
"""
@inline symbol(order::Order) = symbol(order.inst)

"""
    trade_dir(order::Order) -> TradeDir

Determine the trade direction (Buy, Sell, or Null) based on order quantity.

# Arguments
- `order::Order`: The order to analyze

# Returns
- `TradeDir`: Buy for positive quantity, Sell for negative, Null for zero

# Examples
```julia
buy_order = Order(1, instrument, DateTime("2023-01-01"), 100.0, 10.0)
trade_dir(buy_order)   # Returns TradeDir.Buy

sell_order = Order(2, instrument, DateTime("2023-01-01"), 100.0, -10.0)
trade_dir(sell_order)  # Returns TradeDir.Sell
```
"""
@inline trade_dir(order::Order) = trade_dir(order.quantity)

"""
    nominal_value(order::Order) -> Price

Calculate the nominal value of an order (price × absolute quantity).

# Arguments
- `order::Order`: The order to calculate nominal value for

# Returns
- `Price`: The nominal value in quote currency

# Examples
```julia
order = Order(1, instrument, DateTime("2023-01-01"), 100.0, 10.0)
nominal_value(order)  # Returns 1000.0 (100.0 * 10.0)
```
"""
@inline nominal_value(order::Order) = abs(order.quantity) * order.price

function Base.show(io::IO, o::Order{TTime,O,I}) where {TTime,O,I}
    date_formatter = x -> Dates.format(x, "yyyy-mm-dd HH:MM:SS")
    tp_str = isnan(o.take_profit) ? "—" : "$(format_quote(o.inst, o.take_profit)) $(o.inst.quote_symbol)"
    sl_str = isnan(o.stop_loss) ? "—" : "$(format_quote(o.inst, o.stop_loss)) $(o.inst.quote_symbol)"
    print(io, "[Order] $(o.inst.symbol) " *
              "date=$(date_formatter(o.date)) " *
              "price=$(format_quote(o.inst, o.price)) $(o.inst.quote_symbol) " *
              "qty=$(format_base(o.inst, o.quantity)) $(o.inst.base_symbol) " *
              "tp=$(tp_str) " *
              "sl=$(sl_str)")
end

Base.show(order::Order{TTime,O,I}) where {TTime,O,I} = Base.show(stdout, order)
