"""
Return the rejection reason for a proposed fill impact.

Initial-margin checks enforce `equity_after >= init_margin_after`.
For `MarginRequirement.PercentNotional`, this is an IMR/MMR-style equity-fraction
model (required margin is `rate * abs(notional)`).
"""
@inline function check_fill_constraints(
    acc::Account{TTime},
    pos::Position{TTime},
    impact::FillPlan
)::OrderRejectReason.T where {TTime<:Dates.AbstractTime}
    inst = pos.inst
    settle_idx = inst.settle_cash_index
    margin_idx = inst.margin_cash_index
    inc_qty = calc_exposure_increase_quantity(pos.quantity, impact.fill_qty)

    if acc.funding == AccountFunding.FullyFunded && inc_qty < 0
        return OrderRejectReason.ShortNotAllowed
    end

    if inst.spec.contract_kind == ContractKind.Option
        return _check_option_fill_constraints(acc, pos, impact, inc_qty)
    end

    # No added exposure -> no margin check needed.
    # This intentionally lets close-only fills (e.g. liquidation)
    # bypass incremental initial-margin rejection.
    inc_qty == 0 && return OrderRejectReason.None

    # Compute equity and margin after the fill
    cash_effect = impact.cash_delta_settle + impact.value_delta_settle

    if acc.margin_aggregation == MarginAggregation.PerCurrency
        if margin_idx == settle_idx
            equity_after = acc.ledger.equities[settle_idx] + cash_effect
            init_after = acc.ledger.init_margin_used[settle_idx] + impact.init_margin_delta
            if equity_after - init_after < 0
                return OrderRejectReason.InsufficientInitialMargin
            end
        else
            # Distinct margin/settle currencies: require non-negative available funds in both
            # post-fill states, since cash/value effects land in settle ccy while margin usage
            # changes in margin ccy.
            margin_equity_after = acc.ledger.equities[margin_idx]
            margin_init_after = acc.ledger.init_margin_used[margin_idx] + impact.init_margin_delta
            margin_equity_after - margin_init_after < 0 && return OrderRejectReason.InsufficientInitialMargin

            settle_equity_after = acc.ledger.equities[settle_idx] + cash_effect
            settle_init_after = acc.ledger.init_margin_used[settle_idx]
            settle_equity_after - settle_init_after < 0 && return OrderRejectReason.InsufficientInitialMargin
        end
        return OrderRejectReason.None
    else
        equity_after = equity_base_ccy(acc) + to_base(acc, settle_idx, cash_effect)
        init_after = init_margin_used_base_ccy(acc) + to_base(acc, margin_idx, impact.init_margin_delta)
        if equity_after - init_after < 0
            return OrderRejectReason.InsufficientInitialMargin
        end
        return OrderRejectReason.None
    end
end

function _check_option_strategy_constraints(
    acc::Account,
    equity_delta_by_cash::Vector{Price},
    projected_option_init::Vector{Price},
    current_option_init::Vector{Price},
)::OrderRejectReason.T
    if acc.margin_aggregation == MarginAggregation.PerCurrency
        @inbounds for i in eachindex(acc.ledger.init_margin_used)
            equity_after = acc.ledger.equities[i] + equity_delta_by_cash[i]
            init_after = acc.ledger.init_margin_used[i] - current_option_init[i] + projected_option_init[i]
            if equity_after - init_after < 0
                return OrderRejectReason.InsufficientInitialMargin
            end
        end
        return OrderRejectReason.None
    else
        equity_after = equity_base_ccy(acc)
        projected_init_base = zero(Price)
        @inbounds for i in eachindex(acc.ledger.init_margin_used)
            equity_after += equity_delta_by_cash[i] * _get_rate_base_ccy_idx(acc, i)
            projected = acc.ledger.init_margin_used[i] - current_option_init[i] + projected_option_init[i]
            iszero(projected) && continue
            projected_init_base += projected * _get_rate_base_ccy_idx(acc, i)
        end
        if equity_after - projected_init_base < 0
            return OrderRejectReason.InsufficientInitialMargin
        end
        return OrderRejectReason.None
    end
end

@inline function _account_init_with_option_totals_base(
    acc::Account,
    current_option_init::Vector{Price},
    option_init::Vector{Price},
)::Price
    total = zero(Price)
    @inbounds for i in eachindex(acc.ledger.init_margin_used)
        init_used = acc.ledger.init_margin_used[i] - current_option_init[i] + option_init[i]
        iszero(init_used) && continue
        total += init_used * _get_rate_base_ccy_idx(acc, i)
    end
    total
end

@inline function _check_option_fill_constraints(
    acc::Account{TTime},
    pos::Position{TTime},
    impact::FillPlan,
    inc_qty::Quantity,
)::OrderRejectReason.T where {TTime<:Dates.AbstractTime}
    current_option_init, _ = _stored_option_margin_totals(acc)
    projected_option_init, _ = _project_option_margin_totals_after_fill(acc, pos, impact)
    current_init_base = init_margin_used_base_ccy(acc)

    _check_option_fill_constraints(
        acc,
        pos,
        impact,
        inc_qty,
        current_option_init,
        projected_option_init,
        current_init_base,
    )
end

@inline function _check_option_fill_constraints(
    acc::Account{TTime},
    pos::Position{TTime},
    impact::FillPlan,
    inc_qty::Quantity,
    current_option_init::Vector{Price},
    projected_option_init::Vector{Price},
    current_init_base::Price,
)::OrderRejectReason.T where {TTime<:Dates.AbstractTime}
    inst = pos.inst
    settle_idx = inst.settle_cash_index

    projected_init_base = zero(Price)
    @inbounds for i in eachindex(acc.ledger.init_margin_used)
        projected = acc.ledger.init_margin_used[i] - current_option_init[i] + projected_option_init[i]
        iszero(projected) && continue
        projected_init_base += projected * _get_rate_base_ccy_idx(acc, i)
    end

    # Pure risk-reducing option trades can bypass initial-margin rejection,
    # but closing a protective long leg must still pass the projected margin check.
    if inc_qty == 0.0 && projected_init_base <= current_init_base
        return OrderRejectReason.None
    end

    cash_effect = impact.cash_delta_settle + impact.value_delta_settle

    if acc.margin_aggregation == MarginAggregation.PerCurrency
        @inbounds for i in eachindex(acc.ledger.init_margin_used)
            equity_after = acc.ledger.equities[i]
            i == settle_idx && (equity_after += cash_effect)
            init_after = acc.ledger.init_margin_used[i] - current_option_init[i] + projected_option_init[i]
            if equity_after - init_after < 0
                return OrderRejectReason.InsufficientInitialMargin
            end
        end
        return OrderRejectReason.None
    else
        equity_after = equity_base_ccy(acc) + to_base(acc, settle_idx, cash_effect)
        if equity_after - projected_init_base < 0
            return OrderRejectReason.InsufficientInitialMargin
        end
        return OrderRejectReason.None
    end
end
