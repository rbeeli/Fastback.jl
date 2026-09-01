using Dates

"""
    accrue_interest!(acc, dt; year_basis=365.0)

Accrues interest on cash balances between the last accrual timestamp and `dt`.
Negative balances pay broker borrow rates.

For positive balances, short-sale proceeds on principal-exchange spot shorts are
handled via `broker_short_proceeds_rates`:
- excluded fraction of locked short proceeds is removed from regular lend base,
- optional rebate rate is applied to locked short proceeds.

Rates are evaluated at the accrual window start (`last_interest_dt`).
Interest is applied to both balances and equities and recorded as
`CashflowKind.LendInterest` or `CashflowKind.BorrowInterest` based on net sign.
"""
@inline function _fill_short_proceeds_by_settle_cash!(
    acc::Account,
    proceeds::Vector{Price},
)
    fill!(proceeds, 0.0)

    @inbounds for pos in acc.positions
        qty = pos.quantity
        qty < 0.0 || continue

        inst = pos.inst
        inst.spec.contract_kind == ContractKind.Spot || continue
        inst.spec.settlement == SettlementStyle.PrincipalExchange || continue

        settled_proceeds = -qty * pos.avg_entry_price_settle * inst.spec.multiplier
        isfinite(settled_proceeds) || throw(ArgumentError("Short-proceeds notional must be finite."))
        settled_proceeds > 0.0 || continue

        idx = inst.settle_cash_index
        new_proceeds = proceeds[idx] + settled_proceeds
        isfinite(new_proceeds) || throw(ArgumentError("Short-proceeds total overflowed."))
        proceeds[idx] = new_proceeds
    end

    nothing
end

function accrue_interest!(
    acc::Account{TTime,TBroker},
    dt::TTime;
    year_basis::Real=365.0,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    _validate_account_timestamp(acc, dt)
    isfinite(year_basis) && year_basis > 0 || throw(ArgumentError("year_basis must be positive and finite."))
    if acc.last_interest_dt == TTime(0)
        acc.last_interest_dt = dt
        _advance_account_timestamp!(acc, dt)
        return acc
    end

    dt < acc.last_interest_dt && throw(ArgumentError("Accrual datetime must not go backwards."))

    millis = Dates.value(Dates.Millisecond(dt - acc.last_interest_dt))
    if millis == 0
        _advance_account_timestamp!(acc, dt)
        return acc
    end

    yearfrac = millis / (1000 * 60 * 60 * 24 * Price(year_basis))
    isfinite(yearfrac) || throw(ArgumentError("Interest year fraction must be finite."))

    rate_dt = acc.last_interest_dt
    ledger = acc.ledger
    short_proceeds_by_cash = ledger.short_proceeds_by_cash_buffer
    interest_by_cash = ledger.financing_by_cash_buffer
    fill!(interest_by_cash, 0.0)
    short_proceeds_ready = false
    @inbounds for i in eachindex(ledger.balances)
        bal = ledger.balances[i]
        bal == 0.0 && continue
        cash = ledger.cash[i]
        interest = if bal < 0.0
            borrow_rate, _ = broker_interest_rates(acc.broker, cash, rate_dt, bal)
            isfinite(borrow_rate) || throw(ArgumentError("Broker borrow rate must be finite."))
            bal * borrow_rate * yearfrac
        else
            exclude_fraction, rebate_rate = broker_short_proceeds_rates(acc.broker, cash, rate_dt)
            isfinite(exclude_fraction) || throw(ArgumentError("Short-proceeds excluded fraction must be finite."))
            0.0 <= exclude_fraction <= 1.0 || throw(ArgumentError("Short-proceeds excluded fraction must be between zero and one."))
            isfinite(rebate_rate) || throw(ArgumentError("Short-proceeds rebate rate must be finite."))

            locked = 0.0
            if exclude_fraction != 0.0 || rebate_rate != 0.0
                if !short_proceeds_ready
                    _fill_short_proceeds_by_settle_cash!(acc, short_proceeds_by_cash)
                    short_proceeds_ready = true
                end
                locked = min(bal, short_proceeds_by_cash[i])
            end

            lend_base = max(0.0, bal - exclude_fraction * locked)
            _, lend_rate = broker_interest_rates(acc.broker, cash, rate_dt, lend_base)
            isfinite(lend_rate) || throw(ArgumentError("Broker lend rate must be finite."))
            lend_base * lend_rate * yearfrac + locked * rebate_rate * yearfrac
        end
        isfinite(interest) || throw(ArgumentError("Interest amount must be finite."))
        interest == 0.0 && continue
        isfinite(ledger.balances[i] + interest) || throw(ArgumentError("Interest produces a non-finite balance."))
        isfinite(ledger.equities[i] + interest) || throw(ArgumentError("Interest produces non-finite equity."))
        interest_by_cash[i] = interest
    end

    @inbounds for i in eachindex(interest_by_cash)
        interest = interest_by_cash[i]
        interest == 0.0 && continue
        _adjust_cash_idx!(ledger, i, interest)
        kind = interest >= 0 ? CashflowKind.LendInterest : CashflowKind.BorrowInterest
        _record_cashflow!(acc, dt, kind, i, interest, 0)
    end

    acc.last_interest_dt = dt
    _advance_account_timestamp!(acc, dt)
    acc
end
