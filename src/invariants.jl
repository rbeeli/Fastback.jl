"""
    recompute_equities(acc)

Rebuild account equities from balances and open positions.
Starts from `acc.balances` and adds each position's settlement-currency
value for asset/cash-settled instruments. Variation-margin positions are
expected to carry zero `value_quote`.
"""
function recompute_equities(acc::Account)
    equities = copy(acc.balances)

    @inbounds for pos in acc.positions
        inst = pos.inst
        settlement = inst.settlement

        if settlement == SettlementStyle.VariationMargin
            iszero(pos.value_quote) || throw(AssertionError("Variation-margin position $(inst.symbol) must have zero value_quote."))
            continue
        end

        val_quote = pos.value_quote
        iszero(val_quote) && continue

        settle_idx = inst.settle_cash_index
        settle_idx > 0 || throw(AssertionError("Instrument $(inst.symbol) has unset settle_cash_index."))

        equities[settle_idx] += to_settle(acc, inst, val_quote)
    end

    equities
end

"""
    recompute_margins(acc) -> init, maint

Rebuild the initial and maintenance margin usage vectors by summing the
per-position stored margins into their settlement cash indices.
"""
function recompute_margins(acc::Account)
    init = zero.(acc.init_margin_used)
    maint = zero.(acc.maint_margin_used)

    @inbounds for pos in acc.positions
        settle_idx = pos.inst.settle_cash_index
        settle_idx > 0 || throw(AssertionError("Instrument $(pos.inst.symbol) has unset settle_cash_index."))

        init[settle_idx] += pos.init_margin_settle
        maint[settle_idx] += pos.maint_margin_settle
    end

    return init, maint
end

@inline recompute_init_margin(acc::Account) = first(recompute_margins(acc))
@inline recompute_maint_margin(acc::Account) = last(recompute_margins(acc))

"""
    check_invariants(acc; atol=1e-9, rtol=1e-9)

Assert internal account invariants by recomputing derived vectors and
validating per-position settlement, pricing, and indexing rules.
Throws an `AssertionError` on the first violation and returns `true`
otherwise.
"""
function check_invariants(acc::Account; atol::Real=1e-9, rtol::Real=1e-9)
    @inbounds for pos in acc.positions
        inst = pos.inst

        inst.quote_cash_index > 0 || throw(AssertionError("Instrument $(inst.symbol) has unset quote_cash_index."))
        inst.settle_cash_index > 0 || throw(AssertionError("Instrument $(inst.symbol) has unset settle_cash_index."))
        pos.index == inst.index || throw(AssertionError("Position index $(pos.index) must equal instrument index $(inst.index) for $(inst.symbol)."))

        if pos.quantity != 0.0
            isfinite(pos.mark_price) || throw(AssertionError("Position $(inst.symbol) must have a finite mark_price when exposure is non-zero."))
            isfinite(pos.last_price) || throw(AssertionError("Position $(inst.symbol) must have a finite last_price when exposure is non-zero."))
            pos.mark_time != typeof(pos.mark_time)(0) || throw(AssertionError("Position $(inst.symbol) must have a mark_time when exposure is non-zero."))
        end

        if inst.settlement == SettlementStyle.VariationMargin
            isapprox(pos.value_quote, 0.0; atol=atol, rtol=rtol) || throw(AssertionError("Variation-margin position $(inst.symbol) must have zero value_quote."))
            isapprox(pos.value_settle, 0.0; atol=atol, rtol=rtol) || throw(AssertionError("Variation-margin position $(inst.symbol) must have zero value_settle."))
            isapprox(pos.pnl_quote, 0.0; atol=atol, rtol=rtol) || throw(AssertionError("Variation-margin position $(inst.symbol) must have zero pnl_quote."))
            isapprox(pos.pnl_settle, 0.0; atol=atol, rtol=rtol) || throw(AssertionError("Variation-margin position $(inst.symbol) must have zero pnl_settle."))
        else
            isapprox(pos.avg_settle_price, pos.avg_entry_price; atol=atol, rtol=rtol) ||
                throw(AssertionError("Position $(inst.symbol) avg_settle_price must match avg_entry_price for non-variation settlement."))
            val_settle_expected = to_settle(acc, inst, pos.value_quote)
            isapprox(pos.value_settle, val_settle_expected; atol=atol, rtol=rtol) ||
                throw(AssertionError("Position $(inst.symbol) value_settle cache is stale (expected $(val_settle_expected), found $(pos.value_settle))."))
            pnl_settle_expected = to_settle(acc, inst, pos.pnl_quote)
            isapprox(pos.pnl_settle, pnl_settle_expected; atol=atol, rtol=rtol) ||
                throw(AssertionError("Position $(inst.symbol) pnl_settle cache is stale (expected $(pnl_settle_expected), found $(pos.pnl_settle))."))
        end
    end

    equities_recomputed = recompute_equities(acc)
    isapprox(acc.equities, equities_recomputed; atol=atol, rtol=rtol) ||
        throw(AssertionError("Stored equities do not match recomputed equities."))

    init_recomputed, maint_recomputed = recompute_margins(acc)
    isapprox(acc.init_margin_used, init_recomputed; atol=atol, rtol=rtol) ||
        throw(AssertionError("Stored init_margin_used does not match recomputed values."))
    isapprox(acc.maint_margin_used, maint_recomputed; atol=atol, rtol=rtol) ||
        throw(AssertionError("Stored maint_margin_used does not match recomputed values."))

    return true
end
