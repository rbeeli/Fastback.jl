@inline calc_realized_pnl(order::Order) = order.execution.realized_pnl

# @inline function calc_realized_return(order::Order; zero_value=0.0)
#     order.execution.realized_pnl != 0 ? calc_realized_pnl(order) / (order.execution.pos_avg_price * abs(order.execution.realized_quantity)) : zero_value
# end

@inline function calc_realized_price_return(order::Order; zero_value=0.0)
    order.execution.realized_pnl != 0 ? sign(order.execution.pos_quantity) * (order.execution.price / order.execution.pos_avg_price - 1.0) : zero_value
end
