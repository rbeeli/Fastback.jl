struct Execution{OData,IData}
    order::Order{OData,IData}
    seq::Int
    dt::DateTime
    fill_price::Price              # price at which the order was filled
    fill_quantity::Quantity        # negative = short selling
    remaining_quantity::Quantity   # remaining (unfilled) quantity after the order was (partially) filled
    realized_pnl::Price            # realized P&L from exposure reduction (covering) incl. fees
    realized_quantity::Quantity    # quantity of the existing position that was covered by the order
    fees_ccy::Price                # paid fees in account currency
    pos_quantity::Quantity         # quantity of the existing position
    pos_price::Price               # average price of the existing position
end

@inline nominal_value(exe::Execution) = exe.fill_price * abs(exe.fill_quantity)

@inline function realized_pnl(exe::Execution)
    exe.realized_pnl
end

# @inline function realized_return(exe::Execution; zero_value=0.0)
#     # TODO: fees calculation
#     if exe.realized_pnl != 0
#         sign(exe.pos_quantity) * (exe.price / exe.pos_avg_price - 1)
#     else
#         zero_value
#     end
# end

function fill_order!(
    acc::TAccount,
    order::Order{O,I},
    dt::DateTime,
    fill_price
    ;
    fill_quantity=NaN,     # fill quantity, if not provided, order quantity is used (complete fill)
    fees_ccy=0,            # fixed fees in account currency
    fees_pct=0,            # relative fees as percentage of order value, e.g. 0.001 = 0.1%
)::Execution{O,I} where {TAccount,O,I}
    # positions are netted using weighted average price,
    # hence only one static position per instrument is maintained

    pos = @inbounds acc.positions[order.inst.index]

    # set fill quantity if not provided
    if isnan(fill_quantity)
        fill_quantity = order.quantity
    end
    remaining_quantity = order.quantity - fill_quantity

    # calculate paid fees
    fees_ccy += fees_pct * fill_price * abs(fill_quantity)

    # realized P&L
    realized_quantity = calc_realized_quantity(pos.quantity, fill_quantity)
    realized_pnl = 0.0
    if realized_quantity != 0.0
        # order is reducing exposure (covering), calculate realized P&L
        realized_pnl = (fill_price - pos.avg_price) * realized_quantity
        pos.pnl -= realized_pnl
    end
    realized_pnl -= fees_ccy

    # execution sequence number
    seq = acc.execution_seq
    acc.execution_seq += 1

    # create execution object
    exe = Execution(
        order,
        seq,
        dt,
        fill_price,
        fill_quantity,
        remaining_quantity,
        realized_pnl,
        realized_quantity,
        fees_ccy,
        pos.quantity,
        pos.avg_price,
    )

    # calculate new exposure
    new_exposure = pos.quantity + fill_quantity
    if new_exposure == 0.0
        # no more exposure
        pos.avg_price = 0.0
    else
        # update average price of position
        if sign(new_exposure) != sign(pos.quantity)
            # handle transitions from long to short and vice versa
            pos.avg_price = fill_price
        elseif abs(new_exposure) > abs(pos.quantity)
            # exposure is increased, update average price
            pos.avg_price = (pos.avg_price * pos.quantity + fill_price * fill_quantity) / new_exposure
        end
        # else: exposure is reduced, no need to update average price
    end

    # update position quantity
    pos.quantity = new_exposure

    # update account balance and equity incl. fees
    acc.balance -= fill_quantity * fill_price + fees_ccy
    acc.equity -= fees_ccy

    # update P&L of position and account equity (w/o fees, already accounted for)
    update_pnl!(acc, pos, fill_price)

    push!(pos.executions, exe)
    push!(acc.executions, exe)

    exe
end
