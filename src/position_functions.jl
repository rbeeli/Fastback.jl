
# quantity negative for shorts, thus works for both long and short
@inline function calc_pnl(pos::Position, ob::OrderBook)
    pos.quantity * (fill_price(-pos.quantity, ob; zero_price=0.0) - pos.avg_price)
end


"""
Calculates the return of a position. The return is based on the weighted average price of the position
and the current price of the asset based on order book data.

# Arguments
- `position`: Position object.
- `ob`: Order book instance with instrument corresponding to the position. Used to calculate the current price of the asset.
"""
@inline function calc_return(pos::Position, ob::OrderBook)
    qty = pos.quantity
    if qty == 0.0
        return zero(qty)
    end
    sign(qty) * (fill_price(-qty, ob) - pos.avg_price) / pos.avg_price
end


"""
Calculates the quantity that is covered by a order of an existing position.
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
calc_covering_quantity(10, -30) # returns 10
calc_covering_quantity(-10, 30) # returns -10
calc_covering_quantity(10, 5)   # returns 0
```
"""
@inline function calc_covering_quantity(position_qty, order_qty)
    (position_qty * order_qty < 0) ? sign(position_qty) * min(abs(position_qty), abs(order_qty)) : zero(position_qty)
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
    (position_qty * order_qty > zero(position_qty)) ? order_qty : max(0, abs(order_qty) - abs(position_qty)) * sign(order_qty)
end


function calc_weighted_avg_price(pos_avg_price, pos_qty, order_price, order_qty)
    if pos_qty * order_qty >= zero(pos_qty)  # same sign
        increase_qty = calc_exposure_increase_quantity(pos_qty, order_qty)
        return (pos_avg_price * pos_qty + order_price * increase_qty) / (pos_qty + increase_qty)
    else  # different signs
        return order_price
    end
end

@inline match_target_exposure(target_exposure::Price, dir::TradeDir, ob::OrderBook) = target_exposure / fill_price(sign(dir), ob; zero_price=0.0)
