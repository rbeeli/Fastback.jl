"""
    liquidate_all!(acc, dt)

Liquidates all open positions using stored side-aware quotes, returning the generated trades.
Liquidation fills are close-only synthetic fills that bypass active-instrument
and initial-margin rejection by design. Option shorts are closed before option
longs so protected spreads are not temporarily converted into naked shorts by
registration order. When `acc.track_trades == false`, state updates still apply
but the returned vector is empty.
"""
@inline function _liquidate_position!(
    trades::Vector{Trade{TTime}},
    acc::Account{TTime,TBroker},
    pos::Position{TTime},
    dt::TTime,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    qty = pos.quantity
    qty == 0.0 && return nothing
    fill_price, bid, ask = _forced_close_quotes(pos)
    inst = pos.inst
    _validate_option_price(inst, "fill_price", fill_price)
    _validate_option_mark_prices(inst, bid, ask, pos.last_price)

    close_qty = -qty
    mark_for_valuation = _calc_mark_price(inst, qty + close_qty, bid, ask)
    margin_price = margin_reference_price(acc, inst, mark_for_valuation, pos.last_price)
    order = Order(oid!(acc), inst, dt, fill_price, close_qty)
    commission = broker_commission(acc.broker, inst, dt, close_qty, fill_price)
    plan = plan_fill(
        acc,
        pos,
        order,
        dt,
        fill_price,
        mark_for_valuation,
        margin_price,
        close_qty,
        commission.fixed,
        commission.pct,
    )
    trade = _apply_fill_plan!(
        acc,
        pos,
        order,
        dt,
        fill_price,
        bid,
        ask,
        pos.last_price,
        mark_for_valuation,
        plan,
        qty,
        pos.avg_entry_price,
        TradeReason.Liquidation,
    )
    trade === nothing || push!(trades, trade)
    nothing
end

function liquidate_all!(
    acc::Account{TTime,TBroker},
    dt::TTime,
)::Vector{Trade{TTime}} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    trades = Trade{TTime}[]

    @inbounds for pos in acc.positions
        pos.inst.spec.contract_kind == ContractKind.Option || continue
        pos.quantity < 0.0 || continue
        _liquidate_position!(trades, acc, pos, dt)
    end

    for pos in acc.positions
        pos.inst.spec.contract_kind == ContractKind.Option && continue
        _liquidate_position!(trades, acc, pos, dt)
    end

    @inbounds for pos in acc.positions
        pos.inst.spec.contract_kind == ContractKind.Option || continue
        _liquidate_position!(trades, acc, pos, dt)
    end

    trades
end

"""
    liquidate_to_maintenance!(acc, dt; max_steps=10_000)

Liquidates positions until the account is above maintenance requirements.
Liquidation fills are close-only synthetic fills that bypass active-instrument
and initial-margin rejection by design.

Base-currency liquidation ranks full-close candidates by projected base excess
liquidity. Per-currency liquidation first targets the worst excess-liquidity
currency by simulating full closes, then falls back to globally reducing
maintenance if no candidate can directly improve that worst currency. When
`acc.track_trades == false`, state updates still apply but the returned vector is
empty.
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
    fill_price, bid, ask = _forced_close_quotes(pos)
    mark_for_valuation = _calc_mark_price(pos.inst, qty + close_qty, bid, ask)
    margin_price = margin_reference_price(acc, pos.inst, mark_for_valuation, pos.last_price)
    commission = broker_commission(acc.broker, pos.inst, dt, close_qty, fill_price)
    order = Order(0, pos.inst, dt, fill_price, close_qty)
    plan = plan_fill(
        acc,
        pos,
        order,
        dt,
        fill_price,
        mark_for_valuation,
        margin_price,
        close_qty,
        commission.fixed,
        commission.pct,
    )

    current_equity = @inbounds acc.ledger.equities[worst_idx]
    current_maint = @inbounds acc.ledger.maint_margin_used[worst_idx]
    delta_equity = pos.inst.settle_cash_index == worst_idx ? (plan.cash_delta_settle + plan.value_delta_settle) : 0.0
    if pos.inst.spec.contract_kind == ContractKind.Option
        _, projected_option_maint = _project_option_margin_totals_after_fill(acc, pos, plan)
        @inbounds begin
            projected_maint = current_maint -
                              acc.option_maint_by_cash[worst_idx] +
                              projected_option_maint[worst_idx]
            return current_equity + delta_equity - projected_maint
        end
    end
    delta_maint = pos.inst.margin_cash_index == worst_idx ? plan.maint_margin_delta : 0.0
    current_equity - current_maint + delta_equity - delta_maint
end

@inline function _option_maint_base_ccy(acc::Account, maint_by_cash::Vector{Price})::Price
    total = zero(Price)
    @inbounds for i in eachindex(maint_by_cash)
        val = maint_by_cash[i]
        iszero(val) && continue
        total += val * _get_rate_base_ccy_idx(acc, i)
    end
    total
end

@inline function _project_excess_base_after_full_close(
    acc::Account{TTime,TBroker},
    pos::Position{TTime},
    dt::TTime,
    current_equity::Price,
    current_maint::Price,
    current_option_maint::Price,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    qty = pos.quantity
    close_qty = -qty
    fill_price, bid, ask = _forced_close_quotes(pos)
    mark_for_valuation = _calc_mark_price(pos.inst, qty + close_qty, bid, ask)
    margin_price = margin_reference_price(acc, pos.inst, mark_for_valuation, pos.last_price)
    commission = broker_commission(acc.broker, pos.inst, dt, close_qty, fill_price)
    order = Order(0, pos.inst, dt, fill_price, close_qty)
    plan = plan_fill(
        acc,
        pos,
        order,
        dt,
        fill_price,
        mark_for_valuation,
        margin_price,
        close_qty,
        commission.fixed,
        commission.pct,
    )

    delta_equity = (plan.cash_delta_settle + plan.value_delta_settle) *
                   _get_rate_base_ccy_idx(acc, pos.inst.settle_cash_index)

    if pos.inst.spec.contract_kind == ContractKind.Option
        _, projected_option_maint = _project_option_margin_totals_after_fill(acc, pos, plan)
        projected_maint = current_maint - current_option_maint +
                          _option_maint_base_ccy(acc, projected_option_maint)
        return current_equity + delta_equity - projected_maint
    end

    delta_maint = plan.maint_margin_delta * _get_rate_base_ccy_idx(acc, pos.inst.margin_cash_index)
    current_equity - current_maint + delta_equity - delta_maint
end

@inline function _project_excess_base_after_full_close(
    acc::Account{TTime,TBroker},
    pos::Position{TTime},
    dt::TTime,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    _project_excess_base_after_full_close(
        acc,
        pos,
        dt,
        equity_base_ccy(acc),
        maint_margin_used_base_ccy(acc),
        _option_maint_base_ccy(acc, acc.option_maint_by_cash),
    )
end

@inline function _select_base_currency_liquidation_pos(
    acc::Account{TTime,TBroker},
    dt::TTime,
    current_excess::Price,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    best_pos = nothing
    best_improvement = -Inf
    best_margin_contrib = -Inf
    fallback_pos = _largest_maint_contributor(acc)
    current_equity = equity_base_ccy(acc)
    current_maint = maint_margin_used_base_ccy(acc)
    current_option_maint = _option_maint_base_ccy(acc, acc.option_maint_by_cash)

    @inbounds for pos in acc.positions
        qty = pos.quantity
        qty == 0.0 && continue

        excess_after = _project_excess_base_after_full_close(
            acc,
            pos,
            dt,
            current_equity,
            current_maint,
            current_option_maint,
        )
        improvement = excess_after - current_excess
        margin_contrib = pos.maint_margin_settle * _get_rate_base_ccy_idx(acc, pos.inst.margin_cash_index)

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

    fallback_pos
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

        if acc.margin_aggregation == MarginAggregation.BaseCurrency
            max_pos = _select_base_currency_liquidation_pos(
                acc,
                dt,
                excess_liquidity_base_ccy(acc),
            )
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
        _liquidate_position!(trades, acc, max_pos, dt)
    end

    trades
end
