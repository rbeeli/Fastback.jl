"""
    Position{TTime,OData,IData}

Represents a net position in a financial instrument using weighted average cost method.

A position maintains the aggregated exposure for an instrument, tracking the average price,
net quantity, unrealized P&L, and references to the most recent order and trade. Positions
use netting, meaning multiple trades in the same instrument are combined into a single position.

# Type Parameters
- `TTime<:Dates.AbstractTime`: The time type used for timestamps
- `OData`: Type for custom order metadata
- `IData`: Type for custom instrument metadata

# Fields
- `index::UInt`: Unique position index for fast array access and hashing
- `inst::Instrument{IData}`: The instrument this position represents
- `avg_price::Price`: Weighted average entry price in quote currency
- `quantity::Quantity`: Net position size (positive for long, negative for short)
- `pnl_local::Price`: Current unrealized P&L in quote currency
- `last_order::Union{Nothing,Order}`: Reference to the most recent order for this instrument
- `last_trade::Union{Nothing,Trade}`: Reference to the most recent trade for this instrument

# Examples
```julia
# Positions are typically created and managed by the Account
position = get_position(account, instrument)

# Check position state
has_exposure(position)    # true if position is open
is_long(position)        # true for positive quantity
is_short(position)       # true for negative quantity

# Calculate P&L at current market price
current_pnl = calc_pnl_local(position, current_price)
current_return = calc_return_local(position, current_price)
```

See also: `Account`, `Instrument`, `calc_pnl_local`, `has_exposure`
"""
mutable struct Position{TTime<:Dates.AbstractTime,OData,IData}
    const index::UInt               # unique index for each position starting from 1 (used for array indexing and hashing)
    const inst::Instrument{IData}
    avg_price::Price
    quantity::Quantity              # negative = short selling
    pnl_local::Price                # local currency P&L
    last_order::Union{Nothing,Order{TTime,OData,IData}}
    last_trade::Union{Nothing,Trade{TTime,OData,IData}}

    function Position{TTime,OData}(
        index,
        inst::Instrument{IData}
        ;
        avg_price::Price=0.0,
        quantity::Quantity=0.0,
        pnl_local::Price=0.0,
        last_order::Union{Nothing,Order{TTime,OData,IData}}=nothing,
        last_trade::Union{Nothing,Trade{TTime,OData,IData}}=nothing,
    ) where {TTime<:Dates.AbstractTime,OData,IData}
        new{TTime,OData,IData}(index, inst, avg_price, quantity, pnl_local, last_order, last_trade)
    end
end

@inline Base.hash(pos::Position) = pos.index  # custom hash for better performance

"""
    is_long(position::Position) -> Bool

Check if a position represents a long exposure (positive quantity).

# Arguments
- `position::Position`: The position to check

# Returns
- `Bool`: `true` if the position quantity is positive, `false` otherwise
"""
@inline is_long(pos::Position) = pos.quantity > zero(Quantity)

"""
    is_short(position::Position) -> Bool

Check if a position represents a short exposure (negative quantity).

# Arguments
- `position::Position`: The position to check

# Returns
- `Bool`: `true` if the position quantity is negative, `false` otherwise
"""
@inline is_short(pos::Position) = pos.quantity < zero(Quantity)

"""
    trade_dir(position::Position) -> TradeDir

Get the trade direction of a position based on its quantity.

# Arguments
- `position::Position`: The position to analyze

# Returns
- `TradeDir`: Buy for positive quantity, Sell for negative, Null for zero
"""
@inline trade_dir(pos::Position) = trade_dir(pos.quantity)

"""
    has_exposure(position::Position) -> Bool

Check if a position has any exposure (non-zero quantity).

Returns `true` if the position quantity is non-zero, indicating an open position.
This is equivalent to checking `!iszero(position.quantity)`.

# Arguments
- `position::Position`: The position to check

# Returns
- `Bool`: `true` if position has exposure, `false` if flat (no position)

# Examples
```julia
position = get_position(account, instrument)
has_exposure(position)     # false initially

# After opening a position
order = Order(oid!(account), instrument, DateTime("2023-01-01"), 100.0, 10.0)
fill_order!(account, order, DateTime("2023-01-01"), 100.0)
has_exposure(position)     # true after trade
```

See also: [`is_long`](@ref), [`is_short`](@ref), [`Position`](@ref)
"""
@inline has_exposure(pos::Position) = pos.quantity != zero(Quantity)

"""
Calculates the P&L of a position in local currency.

The P&L is based on the weighted average price of the position
and the current closing price, without considering commissions.
Fees are accounted for in the account equity calculation and execution P&L.

# Arguments
- `position`: Position object.
- `close_price`: Current closing price.
"""
@inline function calc_pnl_local(pos::Position, close_price)
    # quantity negative for shorts, thus works for both long and short
    pos.quantity * (close_price - pos.avg_price)
end


"""
Calculates the return of a position in local currency.

The return is based on the weighted average price of the position
and the current closing price, without considering commissions.
Fees are accounted for in the account equity calculation and execution P&L.

# Arguments
- `position`: Position object.
- `close_price`: Current closing price.
"""
@inline function calc_return_local(pos::Position{T,O,I}, close_price) where {T<:Dates.AbstractTime,O,I}
    sign(pos.quantity) * (close_price / pos.avg_price - one(close_price))
end


"""
Calculates the quantity that is covered (realized) by a order of an existing position.
Covered in this context means the exposure is reduced.

# Arguments
- `position_qty`: Current position quantity. A positive value indicates a long position and a negative value indicates a short position.
- `order_qty`: Quantity of order. A positive value indicates a buy order and a negative value indicates a sell order.

# Returns
The quantity of shares used to cover the existing position.
This will be a positive number if it covers a long position, and a negative number if it covers a short position.
If the order doesn't cover any of the existing position (i.e., it extends the current long or short position, or there is no existing position),
the function returns 0.

# Examples
```julia
calc_realized_qty(10, -30) # returns 10
calc_realized_qty(-10, 30) # returns -10
calc_realized_qty(10, 5)   # returns 0
```
"""
@inline function calc_realized_qty(position_qty, order_qty)
    if position_qty * order_qty < zero(position_qty)
        sign(position_qty) * min(abs(position_qty), abs(order_qty))
    else
        zero(position_qty)
    end
end


"""
Calculate the quantity of an order that increases the exposure of an existing position.

# Arguments
- `position_qty`: Current position in shares. A positive value indicates a long position and a negative value indicates a short position.
- `order_qty`: Quantity of shares in the new order. A positive value indicates a buy order and a negative value indicates a sell order.

# Returns
Quantity of shares used to increase the existing position.
If the order doesn't increase the existing position (i.e., it covers part or all of the existing long or short position, or there is no existing position), the function returns 0.

# Examples
```julia
calc_exposure_increase_quantity(10, 20)   # returns 20
calc_exposure_increase_quantity(-10, -20) # returns -20
calc_exposure_increase_quantity(10, -5)   # returns 0
```
"""
@inline function calc_exposure_increase_quantity(position_qty, order_qty)
    if position_qty * order_qty > zero(position_qty)
        order_qty
    else
        max(zero(position_qty), abs(order_qty) - abs(position_qty)) * sign(order_qty)
    end
end

# @inline function match_target_exposure(target_exposure::Price, dir::TradeDir.T, ob::OrderBook{I}) where {I}
#     target_exposure / fill_price(sign(dir), ob; zero_price=0.0)
# end

function Base.show(io::IO, pos::Position)
    print(io, "[Position] $(pos.inst.symbol) " *
              "price=$(format_quote(pos.inst, pos.avg_price)) $(pos.inst.quote_symbol) " *
              "qty=$(format_base(pos.inst, pos.quantity)) $(pos.inst.base_symbol) " *
              "pnl_local=$(format_quote(pos.inst, pos.pnl_local)) $(pos.inst.quote_symbol)")
end

Base.show(pos::Position) = Base.show(stdout, pos)
