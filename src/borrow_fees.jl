using Dates

"""
    accrue_borrow_fees!(acc, dt; year_basis=365.0)

Accrues short borrow fees on principal-exchange spot short positions between each position's
last borrow-fee timestamp and `dt`. The fee notional is based on the absolute neutral last price
(falling back to the liquidation mark if unavailable), charged in the instrument
settlement currency, and applied to both balances and equities. Borrow-fee timestamps
are tracked per position and advanced inside `fill_order!` so accrual windows align
with actual short exposure.
"""
@inline function _borrow_fee_eligible(pos::Position)::Bool
    inst = pos.inst
    pos.quantity < 0.0 &&
    inst.spec.contract_kind == ContractKind.Spot &&
    inst.spec.settlement == SettlementStyle.PrincipalExchange &&
    inst.spec.short_borrow_rate > 0.0
end

@inline function _planned_borrow_fee(
    acc::Account{TTime},
    pos::Position{TTime},
    dt::TTime;
    year_basis::Real=365.0,
)::Price where {TTime<:Dates.AbstractTime}
    _borrow_fee_eligible(pos) || return 0.0
    inst = pos.inst

    last_dt = pos.borrow_fee_dt
    last_dt == TTime(0) && return 0.0

    dt < last_dt && throw(ArgumentError("Accrual datetime must not go backwards."))

    millis = Dates.value(Dates.Millisecond(dt - last_dt))
    millis == 0 && return 0.0

    yearfrac = millis / (1000 * 60 * 60 * 24 * Price(year_basis))
    isfinite(yearfrac) || throw(ArgumentError("Borrow-fee year fraction must be finite."))

    fee_price = isnan(pos.last_price) ? pos.mark_price : pos.last_price
    isfinite(fee_price) || throw(ArgumentError("Borrow fee requires a finite reference price for $(inst.spec.symbol)."))
    # Borrow-fee notional should be non-negative even when contracts trade at negative prices.
    fee_quote = abs(pos.quantity) * abs(fee_price) * inst.spec.multiplier * inst.spec.short_borrow_rate * yearfrac
    isfinite(fee_quote) || throw(ArgumentError("Borrow-fee amount must be finite."))
    fee = to_settle(acc, inst, fee_quote)
    isfinite(fee) || throw(ArgumentError("Borrow-fee settlement amount must be finite."))
    -fee
end

@inline function _accrue_borrow_fee!(
    acc::Account{TTime},
    pos::Position{TTime},
    dt::TTime;
    year_basis::Real=365.0,
) where {TTime<:Dates.AbstractTime}
    isfinite(year_basis) && year_basis > 0 || throw(ArgumentError("year_basis must be positive and finite."))
    _borrow_fee_eligible(pos) || return acc
    amount = _planned_borrow_fee(acc, pos, dt; year_basis=year_basis)
    if amount != 0.0
        settle_idx = pos.inst.settle_cash_index
        _adjust_cash_idx!(acc.ledger, settle_idx, amount)
        _record_cashflow!(acc, dt, CashflowKind.BorrowFee, settle_idx, amount, pos.inst.index)
    end

    pos.borrow_fee_dt = dt
    acc
end

function accrue_borrow_fees!(
    acc::Account{TTime},
    dt::TTime;
    year_basis::Real=365.0,
) where {TTime<:Dates.AbstractTime}
    _validate_account_timestamp(acc, dt)
    isfinite(year_basis) && year_basis > 0 || throw(ArgumentError("year_basis must be positive and finite."))
    amounts_by_cash = acc.ledger.financing_by_cash_buffer
    state = acc._event_state
    fill!(amounts_by_cash, 0.0)
    @inbounds for pos_idx in state.borrow_positions
        pos = acc.positions[pos_idx]
        amount = _planned_borrow_fee(acc, pos, dt; year_basis=year_basis)
        state.borrow_amounts[pos_idx] = amount
        idx = pos.inst.settle_cash_index
        projected = amounts_by_cash[idx] + amount
        isfinite(projected) || throw(ArgumentError("Aggregate borrow-fee amount overflowed."))
        amounts_by_cash[idx] = projected
    end
    @inbounds for i in eachindex(amounts_by_cash)
        amount = amounts_by_cash[i]
        isfinite(acc.ledger.balances[i] + amount) || throw(ArgumentError("Borrow fees produce a non-finite balance."))
        isfinite(acc.ledger.equities[i] + amount) || throw(ArgumentError("Borrow fees produce non-finite equity."))
    end
    @inbounds for pos_idx in state.borrow_positions
        pos = acc.positions[pos_idx]
        amount = state.borrow_amounts[pos_idx]
        if amount != 0.0
            idx = pos.inst.settle_cash_index
            _adjust_cash_idx!(acc.ledger, idx, amount)
            _record_cashflow!(acc, dt, CashflowKind.BorrowFee, idx, amount, pos.inst.index)
        end
        pos.borrow_fee_dt = dt
    end
    _advance_account_timestamp!(acc, dt)
    acc
end
