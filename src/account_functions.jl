
function execute_order!(acc::Account, o::OpenOrder, ba::BidAsk)
    # create new position
    pos = Position(
        o.inst,
        sign(o.dir) * abs(o.size),
        o.dir,
        ba,
        ba.dt,
        open_price(o.dir, ba),
        ba,
        ba.dt,
        close_price(o.dir, ba),
        o.stop_loss,
        o.take_profit,
        Unspecified::CloseReason,
        0.0,        # PnL
        o.data      # user-defined data object
    )
    book_position!(acc, pos, ba)
    return
end


function execute_order!(acc::Account, o::CloseOrder, ba::BidAsk)
    close_position!(acc, o.pos, ba, o.close_reason)
    return
end


function execute_order!(acc::Account, o::CloseAllOrder, ba::BidAsk)
    for pos in acc.open_positions
        close_position!(acc, pos, ba, Unspecified::CloseReason)
    end
    return
end


function book_position!(acc::Account, pos::Position, ba::BidAsk)
    # update P&L of position and account equity
    update_pnl!(acc, pos, ba)

    # add position to portfolio
    push!(acc.open_positions, pos)
    return
end


function update_pnl!(acc::Account, pos::Position, ba::BidAsk)
    # temporarily remove from account equity
    acc.equity -= pos.pnl

    # update P&L of position
    update_pnl!(pos, ba)

    # add updated value to account equity
    acc.equity += pos.pnl
    return
end


function close_position!(acc::Account, pos::Position, ba::BidAsk, close_reason::CloseReason)
    # find in vector of open positions
    idx = findfirst(x -> x === pos, acc.open_positions)
    if isnothing(idx)
        println("WARNING: Position already closed!\n", pos)
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


function update_account!(acc::Account, inst::Instrument, ba::BidAsk)
    # # close orders for given instrument
    # if length(acc.close_orders) > 0
    #     inst_orders = get(acc.close_orders, inst, nothing)
    #     if !isnothing(inst_orders)
    #         for o in inst_orders
    #             execute_order!(acc, o, nbbo)
    #             acc.close_orders_count -= 1
    #         end
    #         empty!(inst_orders)
    #     end
    # end

    # # open orders for given instrument
    # if length(acc.place_orders) > 0
    #     inst_orders = get(acc.place_orders, inst, nothing)
    #     if !isnothing(inst_orders)
    #         for o in inst_orders
    #             execute_order!(acc, o, nbbo)
    #             acc.place_orders_count -= 1
    #         end
    #         empty!(inst_orders)
    #     end
    # end

    # value open positions for given instrument
    for pos in acc.open_positions
        if pos.inst === inst
            # update P&L of position and account equity
            update_pnl!(acc, pos, ba)
        end
    end

    return
end
