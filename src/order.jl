using Dates

struct Order{OData,IData,TAccount}
    seq::Int
    acc::TAccount
    inst::Instrument{IData}
    dt::DateTime
    price::Price
    quantity::Quantity            # negative = short selling
    data::OData

    function Order(
        acc::TAccount,
        inst::Instrument{IData},
        dt,
        price,
        quantity
        ;
        data::OData=nothing
    ) where {IData,OData,TAccount}
        seq = acc.order_seq
        acc.order_seq += 1
        new{OData,IData,TAccount}(seq, acc, inst, dt, price, quantity, data)
    end
end

@inline trade_dir(order::Order) = trade_dir(order.quantity)
