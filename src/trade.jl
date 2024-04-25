mutable struct Trade{OData,IData}
    const order::Order{OData,IData}
    const tid::Int
    const dt::DateTime
    const fill_price::Price              # price at which the order was filled
    const fill_quantity::Quantity        # negative = short selling
    const remaining_quantity::Quantity   # remaining (unfilled) quantity after the order was (partially) filled
    const realized_pnl::Price            # realized P&L from exposure reduction (covering) incl. fees
    const realized_quantity::Quantity    # quantity of the existing position that was covered by the order
    const fee_ccy::Price                # paid fees in account currency
    const pos_quantity::Quantity         # quantity of the existing position
    const pos_price::Price               # average price of the existing position
end

@inline order(exe::Trade) = exe.order
@inline instrument(exe::Trade) = instrument(order(exe))
@inline symbol(exe::Trade) = symbol(instrument(exe))
@inline tid(exe::Trade) = exe.tid
@inline date(exe::Trade) = exe.dt
@inline fill_price(exe::Trade) = exe.fill_price
@inline fill_quantity(exe::Trade) = exe.fill_quantity
@inline remaining_quantity(exe::Trade) = exe.remaining_quantity
@inline realized_pnl(exe::Trade) = exe.realized_pnl
@inline realized_quantity(exe::Trade) = exe.realized_quantity
@inline fee_ccy(exe::Trade) = exe.fee_ccy
@inline pos_quantity(exe::Trade) = exe.pos_quantity
@inline pos_price(exe::Trade) = exe.pos_price
@inline nominal_value(exe::Trade) = exe.fill_price * abs(exe.fill_quantity)

# @inline function realized_return(exe::Trade; zero_value=0.0)
#     # TODO: fees calculation
#     if exe.realized_pnl != 0
#         sign(exe.pos_quantity) * (exe.price / exe.pos_avg_price - 1)
#     else
#         zero_value
#     end
# end
