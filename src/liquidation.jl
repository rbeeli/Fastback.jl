function liquidate_all!(
    acc::Account{TTime},
    dt::TTime;
    commission::Price=0.0,
)::Vector{Trade{TTime}} where {TTime<:Dates.AbstractTime}
    trades = Trade{TTime}[]
    for pos in acc.positions
        qty = pos.quantity
        qty == 0.0 && continue
        isnan(pos.mark_price) && throw(ArgumentError("Cannot liquidate position $(pos.inst.symbol): mark price is NaN"))
        order = Order(oid!(acc), pos.inst, dt, pos.mark_price, -qty)
        trade = fill_order!(acc, order, dt, pos.mark_price; commission=commission, allow_inactive=true, trade_reason=TradeReason.Liquidation)
        trade isa Trade || throw(ArgumentError("Liquidation rejected for $(pos.inst.symbol) with reason $(trade)"))
        push!(trades, trade)
    end
    trades
end
