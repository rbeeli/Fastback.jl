"""
    liquidate_all!(acc, dt)

Liquidates all open positions at their current marks, returning the generated trades.
Throws `OrderRejectError` if a liquidation fill is rejected by risk checks.
"""
function liquidate_all!(
    acc::Account{TTime,TBroker},
    dt::TTime,
)::Vector{Trade{TTime}} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
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
            allow_inactive=true,
            trade_reason=TradeReason.Liquidation,
        )
        trade isa Trade || throw(ArgumentError("Liquidation rejected for $(pos.inst.symbol) with reason $(trade)"))
        push!(trades, trade)
    end
    trades
end

"""
    liquidate_to_maintenance!(acc, dt; max_steps=10_000)

Liquidates positions until the account is above maintenance requirements.
Throws `OrderRejectError` if a liquidation fill is rejected by risk checks.

Per-currency liquidation first targets the worst excess-liquidity currency by
simulating full closes, then falls back to globally reducing maintenance if no
candidate can directly improve that worst currency.
"""
@inline function _largest_maint_contributor(
    acc::Account,
)
    max_pos = nothing
    max_score = -Inf

    @inbounds for pos in acc.positions
        qty = pos.quantity
        qty == 0.0 && continue

        score = pos.maint_margin_settle * _get_rate_base_ccy_idx(acc, pos.inst.margin_cash_index)

        if score > max_score ||
           (score == max_score && (max_pos === nothing || pos.inst.index < max_pos.inst.index))
            max_score = score
            max_pos = pos
        end
    end

    max_pos
end

@inline function _worst_excess_currency(
    acc::Account,
)
    worst_idx = 0
    worst_excess = 0.0

    @inbounds for i in eachindex(acc.ledger.maint_margin_used)
        excess = acc.ledger.equities[i] - acc.ledger.maint_margin_used[i]
        if excess < worst_excess
            worst_excess = excess
            worst_idx = i
        end
    end

    worst_idx, worst_excess
end

@inline function _project_excess_after_full_close(
    acc::Account{TTime,TBroker},
    pos::Position{TTime},
    dt::TTime,
    worst_idx::Int,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    qty = pos.quantity
    close_qty = -qty
    fill_price = pos.mark_price
    margin_price = margin_reference_price(acc, fill_price, pos.last_price)
    commission = broker_commission(acc.broker, pos.inst, dt, close_qty, fill_price)
    order = Order(0, pos.inst, dt, fill_price, close_qty)
    plan = plan_fill(
        acc,
        pos,
        order,
        dt,
        fill_price,
        fill_price,
        margin_price,
        close_qty,
        commission.fixed,
        commission.pct,
    )

    current_excess = @inbounds acc.ledger.equities[worst_idx] - acc.ledger.maint_margin_used[worst_idx]
    delta_equity = pos.inst.settle_cash_index == worst_idx ? (plan.cash_delta_settle + plan.value_delta_settle) : 0.0
    delta_maint = pos.inst.margin_cash_index == worst_idx ? plan.maint_margin_delta : 0.0
    current_excess + delta_equity - delta_maint
end

@inline function _select_per_currency_liquidation_pos(
    acc::Account{TTime,TBroker},
    dt::TTime,
    worst_idx::Int,
    worst_excess::Price,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    best_pos = nothing
    best_improvement = -Inf
    best_margin_contrib = -Inf
    fallback_pos = _largest_maint_contributor(acc)

    @inbounds for pos in acc.positions
        qty = pos.quantity
        qty == 0.0 && continue

        excess_after = _project_excess_after_full_close(
            acc,
            pos,
            dt,
            worst_idx,
        )
        improvement = excess_after - worst_excess
        margin_contrib = pos.inst.margin_cash_index == worst_idx ? pos.maint_margin_settle : 0.0

        if best_pos === nothing ||
           improvement > best_improvement ||
           (improvement == best_improvement && margin_contrib > best_margin_contrib) ||
           (improvement == best_improvement && margin_contrib == best_margin_contrib && pos.inst.index < best_pos.inst.index)
            best_improvement = improvement
            best_margin_contrib = margin_contrib
            best_pos = pos
        end
    end

    if best_pos !== nothing && best_improvement > 0.0
        return best_pos
    end

    # No direct improvement for the most-deficient currency: de-risk globally first.
    fallback_pos
end

function liquidate_to_maintenance!(
    acc::Account{TTime,TBroker},
    dt::TTime;
    max_steps::Int=10_000,
)::Vector{Trade{TTime}} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    trades = Trade{TTime}[]
    steps = 0

    while is_under_maintenance(acc)
        steps += 1
        steps > max_steps && throw(ArgumentError("Reached max_steps=$(max_steps) while account remains under maintenance."))

        max_pos = nothing

        if acc.margining_style == MarginingStyle.BaseCurrency
            max_pos = _largest_maint_contributor(acc)
        else
            worst_idx, worst_excess = _worst_excess_currency(acc)

            worst_idx == 0 && throw(ArgumentError("Account under maintenance but no currency deficit detected."))
            max_pos = _select_per_currency_liquidation_pos(
                acc,
                dt,
                worst_idx,
                worst_excess,
            )
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
