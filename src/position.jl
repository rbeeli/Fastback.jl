mutable struct Position{OData,IData,TAccount}
    index::Int64                # unique index for each position starting from 1 (used for array indexing and hashing)
    acc::TAccount
    inst::Instrument{IData}
    quantity::Quantity          # negative = short selling
    executions::Vector{Execution{OData,IData}}
    avg_price::Price
    pnl::Price

    function Position{OData,IData}(
        index,
        acc::TAccount,
        inst::Instrument{IData},
        quantity,
        avg_price,
        pnl
    ) where {OData,IData,TAccount}
        executions = Vector{Execution{OData,IData}}()
        new{OData,IData,TAccount}(index, acc, inst, quantity, executions, avg_price, pnl)
    end
end

Base.hash(pos::Position) = pos.index  # custom hash for better performance

@inline is_long(pos::Position) = pos.quantity > 0
@inline is_short(pos::Position) = pos.quantity < 0
@inline trade_dir(pos::Position) = trade_dir(pos.quantity)
@inline avg_price(pos::Position) = pos.avg_price
@inline quantity(pos::Position) = pos.quantity
@inline pnl(pos::Position) = pos.pnl
@inline executions(pos::Position) = pos.executions

"""
Calculates the P&L of a position.

The P&L is based on the weighted average price of the position
and the current closing price, without considering fees.
Fees are accounted for in the account equity calculation and execution P&L.

# Arguments
- `position`: Position object.
- `close_price`: Current closing price.
"""
@inline function calc_pnl(pos::Position{O,I}, close_price::Price) where {O,I}
    # quantity negative for shorts, thus works for both long and short
    pos.quantity * (close_price - pos.avg_price)
end


"""
Calculates the return of a position.

The return is based on the weighted average price of the position
and the current closing price, without considering fees.
Fees are accounted for in the account equity calculation and execution P&L.

# Arguments
- `position`: Position object.
- `close_price`: Current closing price.
"""
@inline function calc_return(pos::Position{O,I}, close_price::Price) where {O,I}
    sign(pos.quantity) * (close_price / pos.avg_price - 1)
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
calc_realized_quantity(10, -30) # returns 10
calc_realized_quantity(-10, 30) # returns -10
calc_realized_quantity(10, 5)   # returns 0
```
"""
@inline function calc_realized_quantity(position_qty, order_qty)
    if (position_qty * order_qty < 0)
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
