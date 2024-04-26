using Dates

mutable struct Order{OData,IData}
    const oid::Int
    const inst::Instrument{IData}
    const date::DateTime
    const price::Price
    const quantity::Quantity            # negative = short selling
    data::OData

    function Order(
        oid::Int,
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

@inline oid(order::Order) = order.oid
@inline instrument(order::Order) = order.inst
@inline symbol(order::Order) = symbol(instrument(order))
@inline date(order::Order) = order.date
@inline price(order::Order) = order.price
@inline quantity(order::Order) = order.quantity
@inline trade_dir(order::Order) = trade_dir(order.quantity)
@inline data(order::Order) = order.data
