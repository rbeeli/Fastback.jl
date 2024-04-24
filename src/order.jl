using Dates

mutable struct Order{OData,IData}
    const seq::Int
    const inst::Instrument{IData}
    const dt::DateTime
    const price::Price
    const quantity::Quantity            # negative = short selling
    data::OData

    function Order(
        seq::Int,
        inst::Instrument{IData},
        dt::DateTime,
        price::Price,
        quantity::Quantity
        ;
        data::OData=nothing
    ) where {OData,IData}
        new{OData,IData}(seq, inst, dt, price, quantity, data)
    end
end

@inline trade_dir(order::Order) = trade_dir(order.quantity)
