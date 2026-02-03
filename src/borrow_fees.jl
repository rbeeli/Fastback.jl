using Dates

"""
    accrue_borrow_fees!(acc, dt; year_basis=365.0)

Accrues short borrow fees on cash-settled spot short positions between each position's
last borrow-fee timestamp and `dt`. The fee notional is based on the neutral last price
(falling back to the liquidation mark if unavailable), charged in the instrument
settlement currency, and applied to both balances and equities. Borrow-fee timestamps
are tracked per position and advanced inside `fill_order!` so accrual windows align
with actual short exposure.
"""
@inline function _accrue_borrow_fee!(
    acc::Account{TTime},
    pos::Position{TTime},
    dt::TTime;
    year_basis::Real=365.0,
) where {TTime<:Dates.AbstractTime}
    pos.quantity < 0.0 || return acc
    inst = pos.inst
    inst.contract_kind == ContractKind.Spot || return acc
    inst.settlement == SettlementStyle.Cash || return acc
    inst.short_borrow_rate > 0.0 || return acc

    last_dt = pos.borrow_fee_dt
    if last_dt == TTime(0)
        pos.borrow_fee_dt = dt
        return acc
    end

    dt < last_dt && throw(ArgumentError("Accrual datetime must not go backwards."))

    millis = Dates.value(Dates.Millisecond(dt - last_dt))
    millis == 0 && return acc

    yearfrac = millis / (1000 * 60 * 60 * 24 * Price(year_basis))

    fee_price = isnan(pos.last_price) ? pos.mark_price : pos.last_price
    fee_quote = abs(pos.quantity) * fee_price * inst.multiplier * inst.short_borrow_rate * yearfrac
    settle_idx = inst.settle_cash_index
    fee = to_settle(acc, inst, fee_quote)
    if fee != 0.0
        acc.balances[settle_idx] -= fee
        acc.equities[settle_idx] -= fee
        push!(acc.cashflows, Cashflow{TTime}(cfid!(acc), dt, CashflowKind.BorrowFee, settle_idx, -fee, inst.index))
    end

    pos.borrow_fee_dt = dt
    acc
end

function accrue_borrow_fees!(
    acc::Account{TTime},
    dt::TTime;
    year_basis::Real=365.0,
) where {TTime<:Dates.AbstractTime}
    @inbounds for pos in acc.positions
        _accrue_borrow_fee!(acc, pos, dt; year_basis=year_basis)
    end
    acc
end
