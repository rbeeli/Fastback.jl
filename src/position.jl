mutable struct Position{OData,IData}
    const index::UInt               # unique index for each position starting from 1 (used for array indexing and hashing)
    const inst::Instrument{IData}
    avg_price::Price
    quantity::Quantity              # negative = short selling
    pnl_local::Price                # local currency P&L

    function Position{OData}(
        index,
        inst::Instrument{IData}
        ;
        avg_price::Price=0.0,
        quantity::Quantity=0.0,
        pnl_local::Price=0.0
    ) where {OData,IData}
        new{OData,IData}(index, inst, avg_price, quantity, pnl_local)
    end
end

@inline Base.hash(pos::Position) = pos.index  # custom hash for better performance

@inline is_long(pos::Position) = pos.quantity > zero(Quantity)
@inline is_short(pos::Position) = pos.quantity < zero(Quantity)
@inline trade_dir(pos::Position) = trade_dir(pos.quantity)
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
@inline function calc_return_local(pos::Position{O,I}, close_price) where {O,I}
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

# Tables.jl interface for Vector{Position}
Tables.istable(::Type{<:Vector{<:Position}}) = true
Tables.rowaccess(::Type{<:Vector{<:Position}}) = true
Tables.rows(x::Vector{<:Position}) = x

Tables.schema(x::Vector{<:Position}) = Tables.Schema((:symbol, :quantity, :avg_price, :currency, :pnl), Tuple{String, Float64, Float64, String, Float64})

# Tables.jl interface for individual Position objects
Tables.getcolumn(p::Position, nm::Symbol) = Tables.getcolumn(p, Val(nm))
Tables.getcolumn(p::Position, ::Val{:symbol}) = string(p.inst.symbol)
Tables.getcolumn(p::Position, ::Val{:quantity}) = Float64(p.quantity)
Tables.getcolumn(p::Position, ::Val{:avg_price}) = Float64(p.avg_price)
Tables.getcolumn(p::Position, ::Val{:currency}) = string(p.inst.quote_symbol)
Tables.getcolumn(p::Position, ::Val{:pnl}) = Float64(p.pnl_local)

Tables.columnnames(::Position) = (:symbol, :quantity, :avg_price, :currency, :pnl)
