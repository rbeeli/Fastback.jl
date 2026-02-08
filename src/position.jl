"""
Position state tracked per instrument (see currency/unit semantics note in `contract_math.jl`).

- `avg_entry_price` / `avg_settle_price`: `price` in quote currency
- `avg_entry_price_settle`: `price` translated into settlement currency at fill-time FX (used for realized settle P&L on asset settlement)
- `quantity`: `qty`
- `pnl_quote`, `pnl_settle`, `value_quote`, `value_settle`: cached valuation in quote/settlement currencies
- `init_margin_settle`, `maint_margin_settle`: margin currency (defaults to settlement)
- `mark_price`: last valuation (liquidation) price at `mark_time`
- `last_price`: last traded price used for margin calculations
- `borrow_fee_dt`: last borrow-fee accrual timestamp for asset-settled spot shorts
"""
mutable struct Position{TTime<:Dates.AbstractTime}
    const index::Int                # unique index for each position starting from 1 (used for array indexing and hashing)
    const inst::Instrument{TTime}
    avg_entry_price::Price
    avg_entry_price_settle::Price
    avg_settle_price::Price
    quantity::Quantity              # negative = short selling
    pnl_quote::Price                # quote currency P&L
    pnl_settle::Price               # settlement currency P&L (cached for reporting)
    value_quote::Price              # position value contribution in quote currency
    value_settle::Price             # position value contribution in settlement currency (cached)
    init_margin_settle::Price       # initial margin used in margin currency (defaults to settlement)
    maint_margin_settle::Price      # maintenance margin used in margin currency (defaults to settlement)
    mark_price::Price               # last valuation price
    last_price::Price               # last traded price
    mark_time::TTime                # timestamp of last valuation price
    borrow_fee_dt::TTime            # timestamp of last borrow-fee accrual
    last_order::Union{Nothing,Order{TTime}}
    last_trade::Union{Nothing,Trade{TTime}}

    function Position{TTime}(
        index,
        inst::Instrument{TTime}
        ;
        avg_entry_price::Price=0.0,
        avg_entry_price_settle::Price=0.0,
        avg_settle_price::Price=0.0,
        quantity::Quantity=0.0,
        pnl_quote::Price=0.0,
        pnl_settle::Price=0.0,
        value_quote::Price=0.0,
        value_settle::Price=0.0,
        init_margin_settle::Price=0.0,
        maint_margin_settle::Price=0.0,
        mark_price::Price=Price(NaN),
        last_price::Price=Price(NaN),
        mark_time::TTime=TTime(0),
        borrow_fee_dt::TTime=TTime(0),
        last_order::Union{Nothing,Order{TTime}}=nothing,
        last_trade::Union{Nothing,Trade{TTime}}=nothing,
    ) where {TTime<:Dates.AbstractTime}
        new{TTime}(
            index,
            inst,
            avg_entry_price,
            avg_entry_price_settle,
            avg_settle_price,
            quantity,
            pnl_quote,
            pnl_settle,
            value_quote,
            value_settle,
            init_margin_settle,
            maint_margin_settle,
            mark_price,
            last_price,
            mark_time,
            borrow_fee_dt,
            last_order,
            last_trade
        )
    end
end

@inline Base.hash(pos::Position) = pos.index  # custom hash for better performance

@inline is_long(pos::Position) = pos.quantity > zero(Quantity)
@inline is_short(pos::Position) = pos.quantity < zero(Quantity)

"""
Return the trade direction of the position based on its quantity.
A negative quantity indicates a short position, while a positive quantity indicates a long position.
A zero quantity indicates no position (i.e., flat) -> TradeDir.Null.
"""
@inline trade_dir(pos::Position) = trade_dir(pos.quantity)

"""
Return `true` if the position has non-zero exposure.
"""
@inline has_exposure(pos::Position) = pos.quantity != zero(Quantity)

"""
Calculates position P&L in local currency on the **settlement basis**.

- Uses `avg_settle_price` (not the entry basis) so that variation-margin positions
  compute P&L since the last settlement price.
- For `SettlementStyle.Asset`, this is the usual unrealized P&L.
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
