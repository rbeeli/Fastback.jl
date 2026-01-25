"""
    apply_funding!(acc, inst, dt; funding_rate, mark_price=pos.mark_price)

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
    mark_price::Union{Nothing,Price}=nothing,
) where {TTime<:Dates.AbstractTime}
    inst.contract_kind == ContractKind.Perpetual || throw(ArgumentError("Funding applies only to perpetual instruments."))

    pos = get_position(acc, inst)
    pos.quantity == 0.0 && return acc

    mark = something(mark_price, pos.mark_price)
    (isnan(mark)) && throw(ArgumentError("mark_price must be provided or already set on position."))

    payment_quote = -pos.quantity * mark * inst.multiplier * funding_rate
    settle_idx = inst.settle_cash_index
    quote_idx = inst.quote_cash_index
    rate_q_to_settle = get_rate(acc, quote_idx, settle_idx)
    payment = payment_quote * rate_q_to_settle
    @inbounds begin
        acc.balances[settle_idx] += payment
        acc.equities[settle_idx] += payment
    end
    return acc
end
