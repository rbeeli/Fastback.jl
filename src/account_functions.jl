
function execute_order!(
    acc     ::Account,
    order   ::OpenOrder,
    ba      ::BidAsk
)
    # create new position
    pos = Position(
        order.inst,
        sign(order.dir) * abs(order.size),
        order.dir,
        ba,
        ba.dt,
        open_price(order.dir, ba),
        ba,
        ba.dt,
        close_price(order.dir, ba),
        order.stop_loss,
        order.take_profit,
        NullReason::CloseReason,
        0.0,            # initial PnL
        order.data      # user-defined data object
    )
    book_position!(acc, pos, ba)
    return
end


function execute_order!(
    acc     ::Account,
    order   ::CloseOrder,
    ba      ::BidAsk
)
    close_position!(acc, order.pos, ba, order.close_reason)
    return
end


# function execute_order!(
#     acc     ::Account,
#     order   ::CloseAllOrder,
#     ba      ::BidAsk
# )
#     for i in length(acc.open_positions):-1:1
#         pos = acc.open_positions[i]
#         close_position!(acc, pos, ba, NullReason::CloseReason)
#     end
#     return
# end


function book_position!(
    acc     ::Account,
    pos     ::Position,
    ba      ::BidAsk
)
    # update P&L of position and account equity
    update_pnl!(acc, pos, ba)

    # add position to portfolio
    push!(acc.open_positions, pos)

    return
end


function update_pnl!(
    acc     ::Account,
    pos     ::Position,
    ba      ::BidAsk
)
    # temporarily remove from account equity
    acc.equity -= pos.pnl

    # update P&L of position
    update_pnl!(pos, ba)

    # add updated value to account equity
    acc.equity += pos.pnl

    return
end


function close_position!(
    acc             ::Account,
    pos             ::Position,
    ba              ::BidAsk,
    close_reason    ::CloseReason
)
    # find in vector of open positions
    idx = findfirst(x -> x === pos, acc.open_positions)
    if isnothing(idx)
        printstyled(
            "WARN [Fastback] close_position! - WARNING: Position already closed.", pos, "\n"; color=:yellow);
        return
    end

    pos.close_reason = close_reason

    # update P&L of position and account equity
    update_pnl!(acc, pos, ba)

    # remove from open positions vector
    deleteat!(acc.open_positions, idx)

    # add to closed positions vector
    push!(acc.closed_positions, pos)

    # update account balance
    acc.balance += pos.pnl

    return
end


function update_account!(
    acc     ::Account,
    inst    ::Instrument,
    ba      ::BidAsk
)
    # value open positions for given instrument
    for pos in acc.open_positions
        if pos.inst !== inst
            continue
        end

        # update P&L of position and account equity
        update_pnl!(acc, pos, ba)
    end
    return
end
