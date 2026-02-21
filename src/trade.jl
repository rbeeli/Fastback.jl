using Dates

mutable struct Trade{TTime<:Dates.AbstractTime}
    const order::Order{TTime}
    const tid::Int
    const date::TTime
    const fill_price::Price          # price at which the order was filled
    const fill_qty::Quantity         # negative = short selling
    const remaining_qty::Quantity    # remaining (unfilled) quantity after the order was (partially) filled
    const fill_pnl_settle::Price     # gross additive fill P&L in settlement currency; excludes commissions
    const realized_qty::Quantity     # quantity of the existing position that was covered by the order
    const commission_quote::Price    # paid commission in quote currency
    const commission_settle::Price   # paid commission in settlement currency
    const cash_delta_settle::Price   # actual cash movement for this fill in settlement currency
    const pos_qty::Quantity          # quantity of the existing position
    const pos_price::Price           # average entry price of the existing position
    const reason::TradeReason.T
end

"""
Notional trade value in quote currency (`abs(qty) * abs(price) * multiplier`).
"""
@inline notional_value(t::Trade) = abs(t.fill_price) * abs(t.fill_qty) * t.order.inst.multiplier

"""
Realized notional of the closed portion in quote currency.

Computed on the pre-fill position basis as:
`abs(pos_price) * abs(realized_qty) * abs(multiplier)`.
Returns `0.0` for non-realizing fills.
"""
@inline realized_notional_quote(t::Trade) = abs(t.pos_price) * abs(t.realized_qty) * abs(t.order.inst.multiplier)

"""
Return `true` if the trade realizes any P&L.
"""
@inline is_realizing(t::Trade) = t.realized_qty != 0

"""
Per-unit gross realized return for the closed portion of a position.

This is a price-only return (before costs): it uses `fill_price` and
`pos_price`, signed by the pre-fill position direction (`pos_qty`), and
normalized by `abs(pos_price)`.

Equivalent formula:
`sign(pos_qty) * (fill_price - pos_price) / abs(pos_price)`

Returns `NaN` for non-realizing fills (`realized_qty == 0`) or when
`pos_price == 0` (undefined return base).
"""
@inline function realized_return_gross(t::Trade)
    return if is_realizing(t) && t.pos_price != 0
        sign(t.pos_qty) * ((t.fill_price - t.pos_price) / abs(t.pos_price))
    else
        NaN
    end
end

"""
Per-unit net realized return for the closed portion of a position.

Uses the same price-only return basis as `realized_return_gross`, then subtracts
an allocated commission impact for the realized part of the fill, using
quote-domain normalization:
`abs(pos_price) * abs(realized_qty) * multiplier`.

Returns `NaN` when the return base is undefined (e.g. non-realizing trades,
`pos_price == 0`, or `fill_qty == 0`).
"""
@inline function realized_return_net(t::Trade)
    if !is_realizing(t) || t.pos_price == 0 || t.fill_qty == 0
        return NaN
    end

    gross_ret = sign(t.pos_qty) * ((t.fill_price - t.pos_price) / abs(t.pos_price))
    realized_notional = realized_notional_quote(t)
    if realized_notional == 0
        return NaN
    end

    realized_fraction = abs(t.realized_qty) / abs(t.fill_qty)
    realized_commission_quote = t.commission_quote * realized_fraction
    gross_ret - (realized_commission_quote / realized_notional)
end

function Base.show(io::IO, t::Trade)
    date_formatter = x -> Dates.format(x, "yyyy-mm-dd HH:MM:SS")
    ccy_formatter = x -> @sprintf("%.2f", x)
    inst = t.order.inst
    print(io, "[Trade] " *
              "order=(oid=$(t.order.oid), symbol=$(inst.symbol)) " *
              "tid=$(t.tid) " *
              "date=$(date_formatter(t.date)) " *
              "fill_px=$(format_quote(inst, t.fill_price)) $(inst.quote_symbol) " *
              "fill_qty=$(format_base(inst, t.fill_qty)) $(inst.base_symbol) " *
              "remaining_qty=$(format_base(inst, t.remaining_qty)) $(inst.base_symbol) " *
              "fill_pnl_settle=$(ccy_formatter(t.fill_pnl_settle)) $(inst.settle_symbol) " *
              "realized_qty=$(format_base(inst, t.realized_qty)) $(inst.base_symbol) " *
              "commission_quote=$(format_quote(inst, t.commission_quote)) $(inst.quote_symbol) " *
              "commission_settle=$(ccy_formatter(t.commission_settle)) $(inst.settle_symbol) " *
              "cash_delta_settle=$(ccy_formatter(t.cash_delta_settle)) $(inst.settle_symbol) " *
              "pos_qty=$(format_base(inst, t.pos_qty)) $(inst.base_symbol) " *
              "pos_price=$(format_quote(inst, t.pos_price)) $(inst.quote_symbol) " *
              "reason=$(t.reason)")
end

Base.show(obj::Trade) = Base.show(stdout, obj)
