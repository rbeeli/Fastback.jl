
@inline match_target_exposure(target_exposure::Price, dir::TradeDir, ba::BidAsk) = target_exposure / open_price(dir, ba)

@inline function update_pnl!(pos::Position, ba::BidAsk)
    # update last market price
    pos.last_quote = ba
    pos.last_dt = ba.dt
    pos.last_price = close_price(pos.dir, ba)

    # update P&L
    pos.pnl = pnl_net(pos)
    return
end
