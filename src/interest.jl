using Dates

"""
    set_interest_rates!(acc, cash_symbol; borrow, lend)

Registers annualized borrow/lend rates for the given cash symbol.
Rates are expressed as decimals (e.g. 0.05 for 5%).
"""
function set_interest_rates!(
    acc::Account{TTime},
    cash_symbol::Symbol;
    borrow::Real,
    lend::Real,
) where {TTime<:Dates.AbstractTime}
    idx = cash_index(acc.ledger, cash_symbol)
    @inbounds begin
        acc.ledger.interest_borrow_rate[idx] = Price(borrow)
        acc.ledger.interest_lend_rate[idx] = Price(lend)
    end
    acc
end

"""
    accrue_interest!(acc, dt; year_basis=365.0)

Accrues interest on cash balances between the last accrual timestamp and `dt`.
Positive balances earn `interest_lend_rate`, negative balances pay
`interest_borrow_rate`. Interest is applied to both balances and equities and
recorded as `CashflowKind.LendInterest` or `CashflowKind.BorrowInterest`.
"""
function accrue_interest!(
    acc::Account{TTime},
    dt::TTime;
    year_basis::Real=365.0,
) where {TTime<:Dates.AbstractTime}
    if acc.last_interest_dt == TTime(0)
        acc.last_interest_dt = dt
        return acc
    end

    dt < acc.last_interest_dt && throw(ArgumentError("Accrual datetime must not go backwards."))

    millis = Dates.value(Dates.Millisecond(dt - acc.last_interest_dt))
    millis == 0 && return acc

    yearfrac = millis / (1000 * 60 * 60 * 24 * Price(year_basis))

    cfs = acc.cashflows
    @inbounds for i in eachindex(acc.ledger.balances)
        bal = acc.ledger.balances[i]
        rate = bal >= 0 ? acc.ledger.interest_lend_rate[i] : acc.ledger.interest_borrow_rate[i]
        interest = bal * rate * yearfrac
        interest == 0.0 && continue
        acc.ledger.balances[i] += interest
        acc.ledger.equities[i] += interest
        kind = interest >= 0 ? CashflowKind.LendInterest : CashflowKind.BorrowInterest
        push!(cfs, Cashflow{TTime}(cfid!(acc), dt, kind, i, interest, 0))
    end

    acc.last_interest_dt = dt
    acc
end
