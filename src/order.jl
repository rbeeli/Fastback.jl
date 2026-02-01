using Dates

mutable struct Order{TTime<:Dates.AbstractTime}
    const oid::Int
    const inst::Instrument{TTime}
    const date::TTime
    const price::Price
    const quantity::Quantity   # negative = short selling
    take_profit::Price
    stop_loss::Price

    function Order{TTime}(
        oid,
        inst::Instrument{TTime},
        date::TTime,
        price::Price,
        quantity::Quantity
        ;
        take_profit::Price=Price(NaN),
        stop_loss::Price=Price(NaN),
    ) where {TTime<:Dates.AbstractTime}
        new{TTime}(
            oid,
            inst,
            date,
            price,
            quantity,
            take_profit,
            stop_loss,
        )
    end
end

function Order(
    oid,
    inst::Instrument{TTime},
    date::TTime,
    price::Price,
    quantity::Quantity
    ;
    take_profit::Price=Price(NaN),
    stop_loss::Price=Price(NaN),
) where {TTime<:Dates.AbstractTime}
    Order{TTime}(
        oid,
        inst,
        date,
        price,
        quantity
        ;
        take_profit=take_profit,
        stop_loss=stop_loss,
    )
end

"""
Return the instrument symbol of the given order.
"""
@inline symbol(order::Order) = symbol(order.inst)

"""
Return the trade direction of the order based on its quantity.
A negative quantity indicates a short position, while a positive quantity indicates a long position.
A zero quantity indicates no position (i.e., flat) -> TradeDir.Null.
"""
@inline trade_dir(order::Order) = trade_dir(order.quantity)

"""
Nominal order value in quote currency (abs(qty) * price * multiplier).
"""
@inline nominal_value(order::Order) = abs(order.quantity) * order.price * order.inst.multiplier

function Base.show(io::IO, o::Order{TTime}) where {TTime}
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

Base.show(order::Order{TTime}) where {TTime} = Base.show(stdout, order)
