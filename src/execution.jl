mutable struct Execution{OData,IData}
    const order::Order{OData,IData}
    const seq::Int
    const dt::DateTime
    const fill_price::Price              # price at which the order was filled
    const fill_quantity::Quantity        # negative = short selling
    const remaining_quantity::Quantity   # remaining (unfilled) quantity after the order was (partially) filled
    const realized_pnl::Price            # realized P&L from exposure reduction (covering) incl. fees
    const realized_quantity::Quantity    # quantity of the existing position that was covered by the order
    const fees_ccy::Price                # paid fees in account currency
    const pos_quantity::Quantity         # quantity of the existing position
    const pos_price::Price               # average price of the existing position
end

@inline nominal_value(exe::Execution) = exe.fill_price * abs(exe.fill_quantity)

@inline realized_pnl(exe::Execution) = exe.realized_pnl

# @inline function realized_return(exe::Execution; zero_value=0.0)
#     # TODO: fees calculation
#     if exe.realized_pnl != 0
#         sign(exe.pos_quantity) * (exe.price / exe.pos_avg_price - 1)
#     else
#         zero_value
#     end
# end
