using Dates

"""
    Trade{TTime,OData,IData}

Records the actual execution of an order, capturing all relevant fill and position details.

A trade represents the outcome of executing an order, including the fill price, quantities,
realized P&L, commissions, and the state of the position before the trade.

# Type Parameters
- `TTime<:Dates.AbstractTime`: The time type used for timestamps
- `OData`: Type for custom order metadata
- `IData`: Type for custom instrument metadata

# Fields
- `order::Order{TTime,OData,IData}`: The original order that was executed
- `tid::Int`: Unique trade identifier
- `date::TTime`: Trade execution timestamp
- `fill_price::Price`: Actual execution price in quote currency
- `fill_qty::Quantity`: Executed quantity in base currency (negative for short selling)
- `remaining_qty::Quantity`: Unfilled quantity remaining after this execution
- `realized_pnl::Price`: Realized P&L from position reduction, including commissions
- `realized_qty::Quantity`: Quantity of existing position covered by this trade
- `commission::Price`: Total commission paid in quote currency
- `pos_qty::Quantity`: Position quantity before this trade
- `pos_price::Price`: Position average price before this trade

# Examples
```julia
# Trade is typically created by fill_order!, not directly
trade = fill_order!(account, order, DateTime("2023-01-01"), 100.50)
```

See also: `Order`, `fill_order!`, `Position`
"""
mutable struct Trade{TTime<:Dates.AbstractTime,OData,IData}
    const order::Order{TTime,OData,IData}
    const tid::Int
    const date::TTime
    const fill_price::Price         # price at which the order was filled
    const fill_qty::Quantity        # negative = short selling
    const remaining_qty::Quantity   # remaining (unfilled) quantity after the order was (partially) filled
    const realized_pnl::Price       # realized P&L from exposure reduction (covering) incl. commissions
    const realized_qty::Quantity    # quantity of the existing position that was covered by the order
    const commission::Price         # paid commission in quote currency
    const pos_qty::Quantity         # quantity of the existing position
    const pos_price::Price          # average price of the existing position
end

"""
    nominal_value(trade::Trade) -> Price

Calculate the nominal value of a trade (fill price × absolute fill quantity).

# Arguments
- `trade::Trade`: The trade to calculate nominal value for

# Returns
- `Price`: The nominal value in quote currency

# Examples
```julia
trade = fill_order!(account, order, DateTime("2023-01-01"), 100.50)
nominal_value(trade)  # Returns fill_price * abs(fill_qty)
```
"""
@inline nominal_value(t::Trade) = t.fill_price * abs(t.fill_qty)

"""
    is_realizing(trade::Trade) -> Bool

Check if this trade realizes P&L from an existing position.

A trade is realizing if it reduces an existing position (covering), which generates
realized P&L. This occurs when the trade direction is opposite to the existing position.

# Arguments
- `trade::Trade`: The trade to check

# Returns
- `Bool`: `true` if the trade realizes P&L, `false` otherwise

# Examples
```julia
trade = fill_order!(account, order, DateTime("2023-01-01"), 100.50)
is_realizing(trade)  # Returns true if this trade closed part of a position
```
"""
@inline is_realizing(t::Trade) = t.realized_qty != 0

"""
    realized_return(trade::Trade; zero_value=0.0) -> Float64

Calculate the return rate for the realized portion of a trade.

This function computes the percentage return based on the fill price relative to
the position's average price, accounting for the position direction (long/short).

# Arguments
- `trade::Trade`: The trade to calculate return for
- `zero_value=0.0`: Value to return when no P&L is realized or position price is zero

# Returns
- `Float64`: The realized return as a decimal (e.g., 0.1 for 10% return)

# Examples
```julia
trade = fill_order!(account, order, DateTime("2023-01-01"), 110.0)
realized_return(trade)  # Returns 0.1 if closing a long position opened at 100.0
```
"""
@inline function realized_return(t::Trade; zero_value=0.0)
    return if t.realized_pnl != 0 && t.pos_price != 0
        sign(t.pos_qty) * (t.fill_price / t.pos_price - 1)
    else
        zero_value
    end
end

function Base.show(io::IO, t::Trade)
    date_formatter = x -> Dates.format(x, "yyyy-mm-dd HH:MM:SS")
    ccy_formatter = x -> @sprintf("%.2f", x)
    inst = t.order.inst
    print(io, "[Trade] " *
              "date=$(date_formatter(t.date)) " *
              "fill_px=$(format_quote(inst, t.fill_price)) $(inst.quote_symbol) " *
              "fill_qty=$(format_base(inst, t.fill_qty)) $(inst.base_symbol) " *
              "remain_qty=$(format_base(inst, t.remaining_qty)) $(inst.base_symbol) " *
              "real_pnl=$(ccy_formatter(t.realized_pnl)) $(inst.quote_symbol) " *
              "real_qty=$(format_base(inst, t.realized_qty)) $(inst.base_symbol) " *
              "commission=$(ccy_formatter(t.commission)) $(inst.quote_symbol) " *
              "pos_px=$(format_quote(inst, t.pos_price)) $(inst.quote_symbol) " *
              "pos_qty=$(format_base(inst, t.pos_qty)) $(inst.base_symbol)")
end

Base.show(obj::Trade) = Base.show(stdout, obj)
