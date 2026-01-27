@inline function check_fill_constraints(
    acc::Account{TTime},
    pos::Position{TTime},
    impact::FillPlan
)::OrderRejectReason.T where {TTime<:Dates.AbstractTime}
    inst = pos.inst
    settle_idx = inst.settle_cash_index
    inc_qty = calc_exposure_increase_quantity(pos.quantity, impact.fill_qty)

    # cash account: disallow non-asset instruments, shorts, overdrafts
    if acc.mode == AccountMode.Cash
        if inst.settlement != SettlementStyle.Asset
            return OrderRejectReason.InstrumentNotAllowed
        end
        if impact.new_qty < 0
            return OrderRejectReason.ShortNotAllowed
        end
        if acc.balances[settle_idx] + impact.cash_delta < 0
            return OrderRejectReason.InsufficientCash
        end
        return OrderRejectReason.None
    end

    # margin account specific rules
    if inst.margin_mode == MarginMode.None
        if inst.settlement == SettlementStyle.VariationMargin
            return OrderRejectReason.InstrumentNotAllowed
        end
        if inc_qty < 0
            return OrderRejectReason.ShortNotAllowed
        end
        if inc_qty != 0 && acc.balances[settle_idx] + impact.cash_delta < 0
            return OrderRejectReason.InsufficientCash
        end
    end

    # No added exposure → no margin check needed
    inc_qty == 0 && return OrderRejectReason.None

    # Compute equity and margin after the fill
    value_delta_settle = impact.value_delta_settle
    cash_effect = impact.cash_delta + value_delta_settle

    if acc.margining_style == MarginingStyle.PerCurrency
        equity_after = acc.equities[settle_idx] + cash_effect
        init_after = acc.init_margin_used[settle_idx] + impact.init_margin_delta
        if equity_after - init_after < 0
            return OrderRejectReason.InsufficientInitialMargin
        end
        return OrderRejectReason.None
    else
        equity_after = equity_base_ccy(acc) + to_base(acc, settle_idx, cash_effect)
        init_after = init_margin_used_base_ccy(acc) + to_base(acc, settle_idx, impact.init_margin_delta)
        if equity_after - init_after < 0
            return OrderRejectReason.InsufficientInitialMargin
        end
        return OrderRejectReason.None
    end
end
