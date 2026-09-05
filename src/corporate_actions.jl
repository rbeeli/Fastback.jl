"""
    apply_spot_corporate_action!(
        acc,
        inst,
        dt;
        split_factor=1.0,
        cash_dividend_per_unit=0.0,
    )

Apply a split/reverse split and cash dividend to an open principal-exchange
spot position. `split_factor` is new units per old unit and the dividend is in
the instrument quote currency per pre-action unit. Inputs and subsequent marks
must be raw, unadjusted market data.

The operation adjusts position quantity and price bases, creates a synthetic
post-action mark from the preceding raw quotes, records a signed
`CashflowKind.CashDividend`, and preserves account equity before market moves.
If application fails, the account is poisoned and must not be mutated again.
The operation does not accrue financing or provide replay protection.
"""
function apply_spot_corporate_action!(
    acc::Account{TTime,TBroker},
    inst::Instrument{TTime},
    dt::TTime;
    split_factor::Real=1.0,
    cash_dividend_per_unit::Real=0.0,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    try
        factor = Float64(split_factor)
        dividend = Price(cash_dividend_per_unit)
        isfinite(factor) && factor > 0.0 ||
            throw(ArgumentError("split_factor must be positive and finite."))
        isfinite(dividend) && dividend >= 0.0 ||
            throw(ArgumentError("cash_dividend_per_unit must be non-negative and finite."))
        (factor != 1.0 || dividend != 0.0) ||
            throw(ArgumentError("A corporate action must contain a split or cash dividend."))
        _validate_account_timestamp(acc, dt)

        spec = inst.spec
        spec.contract_kind == ContractKind.Spot &&
            spec.settlement == SettlementStyle.PrincipalExchange ||
            throw(ArgumentError("Corporate actions require a principal-exchange spot instrument."))

        pos = get_position(acc, inst)
        if pos.quantity == 0.0
            _advance_account_timestamp!(acc, dt)
            return acc
        end
        (pos.mark_time != TTime(0) && dt < pos.mark_time) &&
            throw(ArgumentError("Corporate-action datetime $(dt) precedes the last mark $(pos.mark_time)."))
        for (name, value) in (("bid", pos.last_bid), ("ask", pos.last_ask), ("last", pos.last_price))
            isfinite(value) || throw(ArgumentError("Corporate action requires a finite prior raw $(name) for $(spec.symbol)."))
        end
        pos.last_bid <= pos.last_ask ||
            throw(ArgumentError("Corporate action requires non-crossed prior quotes for $(spec.symbol)."))

        adjusted_bid = (pos.last_bid - dividend) / factor
        adjusted_ask = (pos.last_ask - dividend) / factor
        adjusted_last = (pos.last_price - dividend) / factor
        for (name, value) in (
            ("post_action_bid", adjusted_bid),
            ("post_action_ask", adjusted_ask),
            ("post_action_last", adjusted_last),
        )
            isfinite(value) && value > 0.0 ||
                throw(ArgumentError("$(name) must be positive and finite, got $(value)."))
        end
        adjusted_bid <= adjusted_ask || throw(ArgumentError("Post-action bid cannot exceed ask."))

        old_qty = pos.quantity
        new_qty = old_qty * factor
        new_pending_factor = pos.pending_split_factor * factor
        isfinite(new_qty) && new_qty != 0.0 ||
            throw(ArgumentError("Post-action quantity must be finite and non-zero."))
        isfinite(new_pending_factor) && new_pending_factor > 0.0 ||
            throw(ArgumentError("Cumulative pending split factor must be positive and finite."))
        dividend_quote = old_qty * dividend * spec.multiplier
        isfinite(dividend_quote) || throw(ArgumentError("Cash dividend amount overflowed."))
        dividend_settle = to_settle(acc, inst, dividend_quote)

        pos.quantity = new_qty
        pos.avg_entry_price /= factor
        pos.avg_entry_price_settle /= factor
        pos.avg_settle_price /= factor
        pos.pending_split_factor = new_pending_factor
        _update_position_events!(acc, pos, old_qty)

        close_price = _calc_mark_price(inst, new_qty, adjusted_bid, adjusted_ask)
        _update_marks!(
            acc,
            pos,
            dt,
            close_price,
            adjusted_bid,
            adjusted_ask,
            adjusted_last,
            true,
        )

        if dividend_settle != 0.0
            _adjust_cash_idx!(acc.ledger, inst.settle_cash_index, dividend_settle)
            _record_cashflow!(
                acc,
                dt,
                CashflowKind.CashDividend,
                inst.settle_cash_index,
                dividend_settle,
                inst.index,
            )
        end
        _advance_account_timestamp!(acc, dt)
        return acc
    catch
        _poison!(acc)
        rethrow()
    end
end
