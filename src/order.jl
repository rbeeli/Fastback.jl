using Dates

mutable struct Order{OData,IData}
    const oid::Int
    const inst::Instrument{IData}
    const date::DateTime
    const price::Price
    const quantity::Quantity   # negative = short selling
    data::OData

    function Order(
        oid,
        inst::Instrument{IData},
        date::DateTime,
        price::Price,
        quantity::Quantity
        ;
        data::OData=nothing
    ) where {OData,IData}
        new{OData,IData}(oid, inst, date, price, quantity, data)
    end
end

@inline symbol(order::Order) = symbol(order.inst)
@inline trade_dir(order::Order) = trade_dir(order.quantity)

function Base.show(io::IO, o::Order{O,I}) where {O,I}
    date_formatter = x -> Dates.format(x, "yyyy-mm-dd HH:MM:SS")
    print(io, "[Order] $(o.inst.symbol) " *
              "dt=$(date_formatter(o.date)) " *
              "px=$(format_quote(o.inst, o.price)) $(o.inst.quote_asset) " *
              "qty=$(format_base(o.inst, o.quantity)) $(o.inst.base_asset) ")
end

Base.show(order::Order{O,I}) where {O,I} = Base.show(stdout, order)