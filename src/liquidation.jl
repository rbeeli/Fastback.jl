function liquidate_all!(
    acc::Account{TTime},
    dt::TTime;
    commission::Price=0.0,
    commission_pct::Price=0.0,
)::Vector{Trade{TTime}} where {TTime<:Dates.AbstractTime}
    trades = Trade{TTime}[]
    for pos in acc.positions
        qty = pos.quantity
        qty == 0.0 && continue
        order = Order(oid!(acc), pos.inst, dt, pos.mark_price, -qty)
        trade = fill_order!(
            acc,
            order;
            dt=dt,
            fill_price=pos.mark_price,
            bid=pos.mark_price,
            ask=pos.mark_price,
            last=pos.last_price,
            commission=commission,
            commission_pct=commission_pct,
            allow_inactive=true,
            trade_reason=TradeReason.Liquidation,
        )
        trade isa Trade || throw(ArgumentError("Liquidation rejected for $(pos.inst.symbol) with reason $(trade)"))
        push!(trades, trade)
    end
    trades
end

function liquidate_to_maintenance!(
    acc::Account{TTime},
    dt::TTime;
    commission::Price=0.0,
    commission_pct::Price=0.0,
    max_steps::Int=10_000,
)::Vector{Trade{TTime}} where {TTime<:Dates.AbstractTime}
    trades = Trade{TTime}[]
    steps = 0

    while is_under_maintenance(acc)
        steps += 1
        steps > max_steps && throw(ArgumentError("Reached max_steps=$(max_steps) while account remains under maintenance."))

        max_pos = nothing

        if acc.margining_style == MarginingStyle.BaseCurrency
            max_margin_base = -Inf

            @inbounds for pos in acc.positions
                qty = pos.quantity
                qty == 0.0 && continue

                m_base = pos.maint_margin_settle * get_rate_base_ccy(acc, pos.inst.settle_cash_index)
                if m_base > max_margin_base
                    max_margin_base = m_base
                    max_pos = pos
                end
            end
        else
            worst_idx = 0
            worst_excess = 0.0

            @inbounds for i in eachindex(acc.maint_margin_used)
                excess = acc.equities[i] - acc.maint_margin_used[i]
                if excess < worst_excess
                    worst_excess = excess
                    worst_idx = i
                end
            end

            worst_idx == 0 && throw(ArgumentError("Account under maintenance but no currency deficit detected."))

            max_margin_settle = -Inf

            @inbounds for pos in acc.positions
                qty = pos.quantity
                qty == 0.0 && continue
                pos.inst.settle_cash_index == worst_idx || continue

                m_settle = pos.maint_margin_settle
                if m_settle > max_margin_settle
                    max_margin_settle = m_settle
                    max_pos = pos
                end
            end

            if max_pos === nothing
                cash_sym = @inbounds acc.cash[worst_idx].symbol
                throw(ArgumentError("Account under maintenance in $(cash_sym) but has no open positions to liquidate."))
            end
        end

        max_pos === nothing && throw(ArgumentError("Account under maintenance but has no open positions to liquidate."))
        qty = max_pos.quantity
        order = Order(oid!(acc), max_pos.inst, dt, max_pos.mark_price, -qty)
        trade = fill_order!(
            acc,
            order;
            dt=dt,
            fill_price=max_pos.mark_price,
            bid=max_pos.mark_price,
            ask=max_pos.mark_price,
            last=max_pos.last_price,
            commission=commission,
            commission_pct=commission_pct,
            allow_inactive=true,
            trade_reason=TradeReason.Liquidation,
        )
        if trade isa Trade
            push!(trades, trade)
        else
            throw(ArgumentError("Liquidation rejected for $(max_pos.inst.symbol) with reason $(trade)"))
        end
    end

    trades
end
