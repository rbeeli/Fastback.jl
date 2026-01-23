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

    if acc.mode == AccountMode.Cash && impact.new_qty < 0
        return OrderRejectReason.ShortNotAllowed
    end

    new_balance = acc.balances[quote_cash_index] + impact.cash_delta
    if new_balance < 0
        return OrderRejectReason.InsufficientCash
    end

    if acc.mode == AccountMode.Margin
        new_init_used = acc.init_margin_used[quote_cash_index] - pos.margin_init_local + impact.new_init_margin
        equity_after = acc.equities[quote_cash_index] + impact.cash_delta + (impact.new_value_local - pos.value_local)
        if equity_after - new_init_used < 0
            return OrderRejectReason.InsufficientInitialMargin
        end
    end

    return OrderRejectReason.None
end
