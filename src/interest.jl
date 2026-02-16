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
        inst.contract_kind == ContractKind.Spot || continue
        inst.settlement == SettlementStyle.PrincipalExchange || continue

        settled_proceeds = -qty * pos.avg_entry_price_settle * inst.multiplier
        settled_proceeds > 0.0 || continue

        proceeds[inst.settle_cash_index] += settled_proceeds
    end

    nothing
end

function accrue_interest!(
    acc::Account{TTime,TBroker},
    dt::TTime;
    year_basis::Real=365.0,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    if acc.last_interest_dt == TTime(0)
        acc.last_interest_dt = dt
        return acc
    end

    dt < acc.last_interest_dt && throw(ArgumentError("Accrual datetime must not go backwards."))

    millis = Dates.value(Dates.Millisecond(dt - acc.last_interest_dt))
    millis == 0 && return acc

    yearfrac = millis / (1000 * 60 * 60 * 24 * Price(year_basis))

    cfs = acc.cashflows
    rate_dt = acc.last_interest_dt
    ledger = acc.ledger
    short_proceeds_by_cash = ledger.short_proceeds_by_cash_buffer
    short_proceeds_ready = false
    @inbounds for i in eachindex(ledger.balances)
        bal = ledger.balances[i]
        cash = ledger.cash[i]
        interest = if bal < 0.0
            borrow_rate, _ = broker_interest_rates(acc.broker, cash, rate_dt, bal)
            bal * borrow_rate * yearfrac
        else
            exclude_fraction, rebate_rate = broker_short_proceeds_rates(acc.broker, cash, rate_dt)

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
            lend_base * lend_rate * yearfrac + locked * rebate_rate * yearfrac
        end
        interest == 0.0 && continue
        ledger.balances[i] += interest
        ledger.equities[i] += interest
        kind = interest >= 0 ? CashflowKind.LendInterest : CashflowKind.BorrowInterest
        push!(cfs, Cashflow{TTime}(cfid!(acc), dt, kind, i, interest, 0))
    end

    acc.last_interest_dt = dt
    acc
end
