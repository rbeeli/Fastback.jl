"""
    apply_funding!(acc, inst, dt; funding_rate)

Applies a perpetual swap funding cashflow to account balances/equities.
Funding is paid/received in the instrument settlement currency.

`payment = -pos.quantity * mark_price * inst.multiplier * funding_rate`

Positive `funding_rate` means longs pay shorts; negative reverses the flow.
"""
function apply_funding!(
    acc::Account{TTime},
    inst::Instrument{TTime},
    dt::TTime;
    funding_rate::Price,
) where {TTime<:Dates.AbstractTime}
    inst.contract_kind == ContractKind.Perpetual || throw(ArgumentError("Funding applies only to perpetual instruments."))

    pos = get_position(acc, inst)
    pos.quantity == 0.0 && return acc

    funding_price = isnan(pos.mark_price) ? pos.last_price : pos.mark_price
    payment_quote = -pos.quantity * funding_price * inst.multiplier * funding_rate
    settle_idx = inst.settle_cash_index
    payment = to_settle(acc, inst, payment_quote)
    if payment != 0.0
        @inbounds begin
            acc.balances[settle_idx] += payment
            acc.equities[settle_idx] += payment
        end
        push!(acc.cashflows, Cashflow{TTime}(cfid!(acc), dt, CashflowKind.Funding, settle_idx, payment, inst.index))
    end
    return acc
end
