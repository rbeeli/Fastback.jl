@inline function check_cash_account(
    acc::Account{TTime},
    pos::Position{TTime},
    inst::Instrument{TTime},
    impact::FillImpact
)::OrderRejectReason.T where {TTime<:Dates.AbstractTime}
    if inst.margin_mode != MarginMode.None
        return OrderRejectReason.InstrumentNotAllowed
    end
    if inst.settlement != SettlementStyle.Asset
        return OrderRejectReason.InstrumentNotAllowed
    end
    if impact.new_qty < 0
        return OrderRejectReason.ShortNotAllowed
    end
    @inbounds new_balance = acc.balances[inst.settle_cash_index] + impact.cash_delta
    if new_balance < 0
        return OrderRejectReason.InsufficientCash
    end
    return OrderRejectReason.None
end

@inline function check_fill_constraints(
    acc::Account{TTime},
    pos::Position{TTime},
    impact::FillImpact
)::OrderRejectReason.T where {TTime<:Dates.AbstractTime}
    inst = pos.inst
    settle_idx = inst.settle_cash_index
    inc_qty = calc_exposure_increase_quantity(pos.quantity, impact.fill_qty)

    # cash account: disallow shorts and overdrafts
    if acc.mode == AccountMode.Cash
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
    rate_q_to_settle = get_rate(acc, inst.quote_cash_index, settle_idx)
    value_delta_settle = (impact.new_value_local - pos.value_local) * rate_q_to_settle
    cash_effect = impact.cash_delta + value_delta_settle

    if acc.margining_style == MarginingStyle.PerCurrency
        equity_after = acc.equities[settle_idx] + cash_effect
        init_after = acc.init_margin_used[settle_idx] - pos.margin_init_local + impact.new_init_margin
        if equity_after - init_after < 0
            return OrderRejectReason.InsufficientInitialMargin
        end
        return OrderRejectReason.None
    else
        r_settle_base = get_rate_base_ccy(acc, settle_idx)
        equity_after = equity_base_ccy(acc) + cash_effect * r_settle_base
        init_after = init_margin_used_base_ccy(acc) - pos.margin_init_local * r_settle_base + impact.new_init_margin * r_settle_base
        if equity_after - init_after < 0
            return OrderRejectReason.InsufficientInitialMargin
        end
        return OrderRejectReason.None
    end
end
