"""
    apply_funding!(acc, inst, dt; funding_rate)

Applies a perpetual swap funding cashflow to account balances/equities.
Funding is paid/received in the instrument settlement currency.

`payment = -pos.quantity * abs(mark_price) * inst.spec.multiplier * funding_rate`

Positive `funding_rate` means longs pay shorts; negative reverses the flow.
"""
function apply_funding!(
    acc::Account{TTime},
    inst::Instrument{TTime},
    dt::TTime;
    funding_rate::Price,
) where {TTime<:Dates.AbstractTime}
    _validate_account_timestamp(acc, dt)
    inst.spec.contract_kind == ContractKind.Perpetual || throw(ArgumentError("Funding applies only to perpetual instruments."))
    isfinite(funding_rate) || throw(ArgumentError("funding_rate must be finite."))

    pos = get_position(acc, inst)
    if pos.quantity == 0.0
        _advance_account_timestamp!(acc, dt)
        return acc
    end

    funding_price = isnan(pos.mark_price) ? pos.last_price : pos.mark_price
    isfinite(funding_price) || throw(ArgumentError("Funding requires a finite mark or last price for $(inst.spec.symbol)."))
    # Funding notional should be non-negative even when contracts trade at negative prices.
    payment_quote = -pos.quantity * abs(funding_price) * inst.spec.multiplier * funding_rate
    settle_idx = inst.settle_cash_index
    payment = to_settle(acc, inst, payment_quote)
    if payment != 0.0
        _adjust_cash_idx!(acc.ledger, settle_idx, payment)
        _record_cashflow!(acc, dt, CashflowKind.Funding, settle_idx, payment, inst.index)
    end
    _advance_account_timestamp!(acc, dt)
    return acc
end
