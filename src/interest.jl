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
    cash = cash_asset(acc, cash_symbol)
    @inbounds begin
        acc.interest_borrow_rate[cash.index] = Price(borrow)
        acc.interest_lend_rate[cash.index] = Price(lend)
    end
    acc
end

"""
    accrue_interest!(acc, dt; year_basis=365.0)

Accrues interest on cash balances between the last accrual timestamp and `dt`.
Positive balances earn `interest_lend_rate`, negative balances pay
`interest_borrow_rate`. Interest is applied to both balances and equities.
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

    @inbounds @simd for i in eachindex(acc.balances)
        bal = acc.balances[i]
        rate = bal >= 0 ? acc.interest_lend_rate[i] : acc.interest_borrow_rate[i]
        interest = bal * rate * yearfrac
        acc.balances[i] += interest
        acc.equities[i] += interest
    end

    acc.last_interest_dt = dt
    acc
end
