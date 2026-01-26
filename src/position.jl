"""
Position state tracked per instrument (see currency/unit semantics note in `contract_math.jl`).

- `avg_entry_price` / `avg_settle_price`: `price`
- `quantity`: `qty`
- `pnl_quote`, `value_quote`: `*_quote`
- `init_margin_settle`, `maint_margin_settle`: `*_settle`
"""
mutable struct Position{TTime<:Dates.AbstractTime}
    const index::Int                # unique index for each position starting from 1 (used for array indexing and hashing)
    const inst::Instrument{TTime}
    avg_entry_price::Price
    avg_settle_price::Price
    quantity::Quantity              # negative = short selling
    pnl_quote::Price                # quote currency P&L
    value_quote::Price              # position value contribution in quote currency
    init_margin_settle::Price       # initial margin used in settlement currency
    maint_margin_settle::Price      # maintenance margin used in settlement currency
    mark_price::Price               # last valuation price
    last_order::Union{Nothing,Order{TTime}}
    last_trade::Union{Nothing,Trade{TTime}}

    function Position{TTime}(
        index,
        inst::Instrument{TTime}
        ;
        avg_entry_price::Price=0.0,
        avg_settle_price::Price=0.0,
        quantity::Quantity=0.0,
        pnl_quote::Price=0.0,
        value_quote::Price=0.0,
        init_margin_settle::Price=0.0,
        maint_margin_settle::Price=0.0,
        mark_price::Price=Price(NaN),
        last_order::Union{Nothing,Order{TTime}}=nothing,
        last_trade::Union{Nothing,Trade{TTime}}=nothing,
    ) where {TTime<:Dates.AbstractTime}
        new{TTime}(
            index,
            inst,
            avg_entry_price,
            avg_settle_price,
            quantity,
            pnl_quote,
            value_quote,
            init_margin_settle,
            maint_margin_settle,
            mark_price,
            last_order,
            last_trade
        )
    end
end

@inline Base.hash(pos::Position) = pos.index  # custom hash for better performance

@inline is_long(pos::Position) = pos.quantity > zero(Quantity)
@inline is_short(pos::Position) = pos.quantity < zero(Quantity)
@inline trade_dir(pos::Position) = trade_dir(pos.quantity)
@inline has_exposure(pos::Position) = pos.quantity != zero(Quantity)

"""
Calculates position P&L in local currency on the **settlement basis**.

- Uses `avg_settle_price` (not the entry basis) so that variation-margin positions
  compute P&L since the last settlement price.
- For `SettlementStyle.Asset` / `Cash`, this is the usual unrealized P&L.
- For `SettlementStyle.VariationMargin`, the caller settles this value into cash
  and then resets `avg_settle_price` to the mark, so subsequent calls reflect only
  moves after the last settlement.

Fees/commissions are handled elsewhere (execution/account), not here.

# Arguments
- `position`: Position object.
- `close_price`: Current closing price.
"""
@inline function calc_pnl_quote(pos::Position, close_price)
    # quantity negative for shorts, thus works for both long and short
    pos.quantity * (close_price - pos.avg_settle_price) * pos.inst.multiplier
end


"""
Calculates position return on the **entry basis** (strategy-facing).

- Uses `avg_entry_price` so it remains stable even when variation margin rolls the
  settlement basis forward.
- Returns zero when no entry price is defined (flat position or not yet set).
- `avg_entry_price` itself resets when exposure flips sign (new trade reverses the
  position) or when the position is closed to flat; returns are therefore measured
  per exposure leg, not across unrelated long/short swings.
- Ignores commissions/fees; those are incorporated in account equity elsewhere.

# Arguments
- `position`: Position object.
- `close_price`: Current closing price.
"""
@inline function calc_return_quote(pos::Position{T}, close_price) where {T<:Dates.AbstractTime}
    if pos.avg_entry_price == 0
        return zero(close_price)
    end
    sign(pos.quantity) * (close_price / pos.avg_entry_price - one(close_price))
end

"""
Calculates the initial margin requirement in quote currency.

The margin is computed based on the instrument's margin mode and parameters.
For percent notional, the requirement scales with notional value and multiplier.
For fixed per contract, the requirement scales with absolute quantity and the
per-contract amounts are denominated in the instrument settlement currency.

# Arguments
- `inst`: Instrument definition.
- `qty`: Position quantity (positive for long, negative for short).
- `mark`: Current mark or close price.
"""
function margin_init_quote(inst::Instrument, qty, mark)
    qty == 0 && return zero(Price)
    mode = inst.margin_mode
    if mode == MarginMode.None
        return zero(Price)
    elseif mode == MarginMode.PercentNotional
        rate = qty > 0 ? inst.margin_init_long : inst.margin_init_short
        return abs(qty) * mark * inst.multiplier * rate
    elseif mode == MarginMode.FixedPerContract
        per_contract = qty > 0 ? inst.margin_init_long : inst.margin_init_short
        return abs(qty) * per_contract
    end
    return zero(Price)
end

"""
Calculates the maintenance margin requirement in quote currency.

The margin is computed based on the instrument's margin mode and parameters.
For percent notional, the requirement scales with notional value and multiplier.
For fixed per contract, the requirement scales with absolute quantity and the
per-contract amounts are denominated in the instrument settlement currency.

# Arguments
- `inst`: Instrument definition.
- `qty`: Position quantity (positive for long, negative for short).
- `mark`: Current mark or close price.
"""
function margin_maint_quote(inst::Instrument, qty, mark)
    qty == 0 && return zero(Price)
    mode = inst.margin_mode
    if mode == MarginMode.None
        return zero(Price)
    elseif mode == MarginMode.PercentNotional
        rate = qty > 0 ? inst.margin_maint_long : inst.margin_maint_short
        return abs(qty) * mark * inst.multiplier * rate
    elseif mode == MarginMode.FixedPerContract
        per_contract = qty > 0 ? inst.margin_maint_long : inst.margin_maint_short
        return abs(qty) * per_contract
    end
    return zero(Price)
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
              "entry=$(format_quote(pos.inst, pos.avg_entry_price)) $(pos.inst.quote_symbol) " *
              "qty=$(format_base(pos.inst, pos.quantity)) $(pos.inst.base_symbol) " *
              "pnl_quote=$(format_quote(pos.inst, pos.pnl_quote)) $(pos.inst.quote_symbol)")
end

Base.show(pos::Position) = Base.show(stdout, pos)
