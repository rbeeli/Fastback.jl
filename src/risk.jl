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
    @inbounds new_balance = acc.balances[inst.quote_cash_index] + impact.cash_delta
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
    quote_cash_index = inst.quote_cash_index
    inc_qty = calc_exposure_increase_quantity(pos.quantity, impact.fill_qty)

    new_balance = acc.balances[quote_cash_index] + impact.cash_delta

    if acc.mode == AccountMode.Cash
        if impact.new_qty < 0
            return OrderRejectReason.ShortNotAllowed
        end
        if new_balance < 0
            return OrderRejectReason.InsufficientCash
        end
        return OrderRejectReason.None
    end

    if acc.mode == AccountMode.Margin
        if inst.margin_mode == MarginMode.None
            if inst.settlement == SettlementStyle.VariationMargin
                return OrderRejectReason.InstrumentNotAllowed
            end
            if inc_qty < 0
                return OrderRejectReason.ShortNotAllowed
            end
            if inc_qty != 0 && new_balance < 0
                return OrderRejectReason.InsufficientCash
            end
        end

        if inc_qty != 0
            if acc.margining_style == MarginingStyle.PerCurrency
                new_init_used = acc.init_margin_used[quote_cash_index] - pos.margin_init_local + impact.new_init_margin
                equity_after = acc.equities[quote_cash_index] + impact.cash_delta + (impact.new_value_local - pos.value_local)
                if equity_after - new_init_used < 0
                    return OrderRejectReason.InsufficientInitialMargin
                end
            else
                eq_before = equity_base_ccy(acc)
                init_before = init_margin_used_base_ccy(acc)
                r = get_rate_base_ccy(acc, quote_cash_index)
                delta_eq_local = impact.cash_delta + (impact.new_value_local - pos.value_local)
                eq_after = eq_before + delta_eq_local * r
                init_after = init_before - pos.margin_init_local * r + impact.new_init_margin * r
                if eq_after - init_after < 0
                    return OrderRejectReason.InsufficientInitialMargin
                end
            end
        end
    end

    return OrderRejectReason.None
end
