mutable struct Trade{OData,IData}
    const order::Order{OData,IData}
    const tid::Int
    const date::DateTime
    const fill_price::Price              # price at which the order was filled
    const fill_quantity::Quantity        # negative = short selling
    const remaining_quantity::Quantity   # remaining (unfilled) quantity after the order was (partially) filled
    const realized_pnl::Price            # realized P&L from exposure reduction (covering) incl. fees
    const realized_quantity::Quantity    # quantity of the existing position that was covered by the order
    const fee_ccy::Price                 # paid fees in account currency
    const pos_quantity::Quantity         # quantity of the existing position
    const pos_price::Price               # average price of the existing position
end

@inline nominal_value(t::Trade) = t.fill_price * abs(t.fill_quantity)
@inline is_realizing(t::Trade) = t.realized_quantity != 0

# @inline function realized_return(t::Trade; zero_value=0.0)
#     # TODO: fees calculation
#     if t.realized_pnl != 0
#         sign(t.pos_quantity) * (t.price / t.pos_avg_price - 1)
#     else
#         zero_value
#     end
# end
