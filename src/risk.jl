@inline function check_fill_constraints(
    acc::Account{TTime},
    pos::Position{TTime},
    impact::FillPlan
)::OrderRejectReason.T where {TTime<:Dates.AbstractTime}
    inst = pos.inst
    settle_idx = inst.settle_cash_index
    margin_idx = inst.margin_cash_index
    inc_qty = calc_exposure_increase_quantity(pos.quantity, impact.fill_qty)

    if acc.mode == AccountMode.Cash && inc_qty < 0
        return OrderRejectReason.ShortNotAllowed
    end

    # No added exposure → no margin check needed
    inc_qty == 0 && return OrderRejectReason.None

    # Compute equity and margin after the fill
    cash_effect = impact.cash_delta + impact.value_delta_settle

    if acc.margining_style == MarginingStyle.PerCurrency
        if margin_idx == settle_idx
            equity_after = acc.equities[settle_idx] + cash_effect
            init_after = acc.init_margin_used[settle_idx] + impact.init_margin_delta
            if equity_after - init_after < 0
                return OrderRejectReason.InsufficientInitialMargin
            end
        else
            # Distinct margin/settle currencies: require non-negative available funds in both
            # post-fill states, since cash/value effects land in settle ccy while margin usage
            # changes in margin ccy.
            margin_equity_after = acc.equities[margin_idx]
            margin_init_after = acc.init_margin_used[margin_idx] + impact.init_margin_delta
            margin_equity_after - margin_init_after < 0 && return OrderRejectReason.InsufficientInitialMargin

            settle_equity_after = acc.equities[settle_idx] + cash_effect
            settle_init_after = acc.init_margin_used[settle_idx]
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
