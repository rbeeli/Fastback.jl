using Dates

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

@inline symbol(order::Order) = symbol(order.inst)
@inline trade_dir(order::Order) = trade_dir(order.quantity)
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
