using Dates

"""
    accrue_borrow_fees!(acc, dt; year_basis=365.0)

Accrues short borrow fees on asset-settled short positions between the last
accrual timestamp and `dt`. The fee notional is based on the neutral last price
(falling back to the liquidation mark if unavailable), charged in the instrument
settlement currency, and applied to both balances and equities.
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
        fee_price = isnan(pos.last_price) ? pos.mark_price : pos.last_price
        fee_quote = abs(pos.quantity) * fee_price * inst.multiplier * inst.short_borrow_rate * yearfrac
        settle_idx = inst.settle_cash_index
        fee = to_settle(acc, inst, fee_quote)
        fee == 0.0 && continue
        acc.balances[settle_idx] -= fee
        acc.equities[settle_idx] -= fee
        push!(acc.cashflows, Cashflow{TTime}(cfid!(acc), dt, CashflowKind.BorrowFee, settle_idx, -fee, inst.index))
    end

    acc.last_borrow_fee_dt = dt
    acc
end
