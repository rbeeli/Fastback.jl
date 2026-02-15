using Dates

"""
    accrue_interest!(acc, dt; year_basis=365.0)

Accrues interest on cash balances between the last accrual timestamp and `dt`.
Positive balances earn broker lend rates, negative balances pay broker borrow
rates. Rates are evaluated at the accrual window start (`last_interest_dt`).
Interest is applied to both balances and equities and recorded as
`CashflowKind.LendInterest` or `CashflowKind.BorrowInterest`.
"""
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
    @inbounds for i in eachindex(ledger.balances)
        bal = ledger.balances[i]
        cash_symbol = ledger.cash[i].symbol
        borrow_rate, lend_rate = broker_interest_rates(acc.broker, cash_symbol, rate_dt, bal)
        rate = bal >= 0 ? lend_rate : borrow_rate
        interest = bal * rate * yearfrac
        interest == 0.0 && continue
        ledger.balances[i] += interest
        ledger.equities[i] += interest
        kind = interest >= 0 ? CashflowKind.LendInterest : CashflowKind.BorrowInterest
        push!(cfs, Cashflow{TTime}(cfid!(acc), dt, kind, i, interest, 0))
    end

    acc.last_interest_dt = dt
    acc
end
