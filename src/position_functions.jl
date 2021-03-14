
@inline match_position_size(target_value::Price, dir::TradeDir, ba::BidAsk) = target_value / get_open_price(dir, ba)

@inline function update_pnl!(pos::Position, ba::BidAsk)
    # update last market price
    pos.last_quotes = ba
    pos.last_dt = ba.dt
    pos.last_price = get_close_price(pos.dir, ba)

    # update P&L
    pos.pnl = get_pnl_net(pos)
    return
end
