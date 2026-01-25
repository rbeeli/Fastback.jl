using Dates

"""
    accrue_borrow_fees!(acc, dt; year_basis=365.0)

Accrues short borrow fees on asset-settled short positions between the last
accrual timestamp and `dt`. The fee is charged in the instrument quote currency
and applied to both balances and equities.
"""
function accrue_borrow_fees!(
    acc::Account{TTime},
    dt::TTime;
    year_basis::Real=365.0,
) where {TTime<:Dates.AbstractTime}
    if acc.last_borrow_fee_dt == TTime(0)
        acc.last_borrow_fee_dt = dt
        return acc
    end

    dt < acc.last_borrow_fee_dt && throw(ArgumentError("Accrual datetime must not go backwards."))

    millis = Dates.value(Dates.Millisecond(dt - acc.last_borrow_fee_dt))
    millis == 0 && return acc

    yearfrac = millis / (1000 * 60 * 60 * 24 * Price(year_basis))

    @inbounds for pos in acc.positions
        pos.quantity < 0.0 || continue
        inst = pos.inst
        inst.settlement == SettlementStyle.Asset || continue
        inst.short_borrow_rate > 0.0 || continue
        isnan(pos.mark_price) && throw(ArgumentError("Cannot accrue borrow fees: mark price is NaN for $(inst.symbol)"))

        fee = abs(pos.quantity) * pos.mark_price * inst.multiplier * inst.short_borrow_rate * yearfrac
        idx = inst.quote_cash_index
        acc.balances[idx] -= fee
        acc.equities[idx] -= fee
    end

    acc.last_borrow_fee_dt = dt
    acc
end
