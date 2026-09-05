"""
    recompute_equities(acc)

Rebuild account equities from balances and open positions.
Starts from `acc.ledger.balances` and adds each position's settlement-currency
value for principal-exchange instruments. Variation-margin positions are
expected to carry zero `value_quote`.
"""
function recompute_equities(acc::Account)
    equities = copy(acc.ledger.balances)

    @inbounds for pos in acc.positions
        inst = pos.inst
        settlement = inst.spec.settlement

        if settlement == SettlementStyle.VariationMargin
            iszero(pos.value_quote) || throw(AssertionError("Variation-margin position $(inst.spec.symbol) must have zero value_quote."))
            continue
        end

        val_quote = pos.value_quote
        iszero(val_quote) && continue

        settle_idx = inst.settle_cash_index
        settle_idx > 0 || throw(AssertionError("Instrument $(inst.spec.symbol) has unset settle_cash_index."))

        equities[settle_idx] += to_settle(acc, inst, val_quote)
    end

    equities
end

"""
    recompute_margins(acc) -> init, maint

Independently rebuild initial and maintenance margin usage from current
quantities, marks, instrument rules, FX, and option-group offsets.
"""
function _recompute_margin_by_position(acc::Account)
    n = length(acc.positions)
    init_by_pos = zeros(Price, n)
    maint_by_pos = zeros(Price, n)
    option_init, option_maint = _option_margin_by_position(acc)

    @inbounds for i in 1:n
        pos = acc.positions[i]
        inst = pos.inst
        pos.quantity == 0.0 && continue
        if inst.spec.contract_kind == ContractKind.Option
            init_by_pos[i] = option_init[i]
            maint_by_pos[i] = option_maint[i]
        else
            margin_price = margin_reference_price(acc, inst, pos.mark_price, pos.last_price)
            init_by_pos[i] = margin_init_margin_ccy(acc, inst, pos.quantity, margin_price)
            maint_by_pos[i] = margin_maint_margin_ccy(acc, inst, pos.quantity, margin_price)
        end
    end
    init_by_pos, maint_by_pos
end

function recompute_margins(acc::Account)
    init = zero.(acc.ledger.init_margin_used)
    maint = zero.(acc.ledger.maint_margin_used)
    init_by_pos, maint_by_pos = _recompute_margin_by_position(acc)

    @inbounds for i in eachindex(acc.positions)
        pos = acc.positions[i]
        margin_idx = pos.inst.margin_cash_index
        margin_idx > 0 || throw(AssertionError("Instrument $(pos.inst.spec.symbol) has unset margin_cash_index."))

        init[margin_idx] += init_by_pos[i]
        maint[margin_idx] += maint_by_pos[i]
    end

    return init, maint
end

@inline recompute_init_margin(acc::Account) = first(recompute_margins(acc))
@inline recompute_maint_margin(acc::Account) = last(recompute_margins(acc))

function _check_registry_invariants(acc::Account)
    ledger = acc.ledger
    cash_count = length(ledger.cash)
    for (name, values) in (
        ("balances", ledger.balances),
        ("equities", ledger.equities),
        ("init_margin_used", ledger.init_margin_used),
        ("maint_margin_used", ledger.maint_margin_used),
        ("short_proceeds_by_cash_buffer", ledger.short_proceeds_by_cash_buffer),
        ("financing_by_cash_buffer", ledger.financing_by_cash_buffer),
        ("option_init_by_cash", acc.option_init_by_cash),
        ("option_maint_by_cash", acc.option_maint_by_cash),
    )
        length(values) == cash_count ||
            throw(AssertionError("Cash registry and $(name) lengths differ."))
    end
    length(ledger.by_symbol) == cash_count ||
        throw(AssertionError("Cash registry and symbol lookup lengths differ."))

    @inbounds for i in eachindex(ledger.cash)
        cash = ledger.cash[i]
        cash.index == i ||
            throw(AssertionError("Cash $(cash.symbol) has inconsistent registry index $(cash.index), expected $(i)."))
        get(ledger.by_symbol, cash.symbol, 0) == i ||
            throw(AssertionError("Cash $(cash.symbol) has an inconsistent symbol lookup entry."))
    end
    1 <= acc.base_currency.index <= cash_count ||
        throw(AssertionError("Account base currency has an unknown cash index."))
    @inbounds ledger.cash[acc.base_currency.index] === acc.base_currency ||
        throw(AssertionError("Account base currency does not belong to the cash registry."))

    position_count = length(acc.positions)
    length(acc._mark_update_last_indices) == position_count ||
        throw(AssertionError("Position registry and mark-update index lengths differ."))
    length(acc.option_group_id_by_pos) == position_count ||
        throw(AssertionError("Position registry and option-group lookup lengths differ."))
    length(acc.option_position_active) == position_count ||
        throw(AssertionError("Position registry and option-active lookup lengths differ."))
    @inbounds for i in eachindex(acc.positions)
        pos = acc.positions[i]
        inst = pos.inst
        pos.index == i ||
            throw(AssertionError("Position $(inst.spec.symbol) has inconsistent registry index $(pos.index), expected $(i)."))
        inst.index == i ||
            throw(AssertionError("Instrument $(inst.spec.symbol) has inconsistent registry index $(inst.index), expected $(i)."))
        for (name, cash_index) in (
            ("quote", inst.quote_cash_index),
            ("settlement", inst.settle_cash_index),
            ("margin", inst.margin_cash_index),
        )
            1 <= cash_index <= cash_count ||
                throw(AssertionError("Instrument $(inst.spec.symbol) has unknown $(name) cash index $(cash_index)."))
        end
        ledger.cash[inst.quote_cash_index].symbol == inst.spec.quote_symbol ||
            throw(AssertionError("Instrument $(inst.spec.symbol) quote cash handle does not match its specification."))
        ledger.cash[inst.settle_cash_index].symbol == inst.spec.settle_symbol ||
            throw(AssertionError("Instrument $(inst.spec.symbol) settlement cash handle does not match its specification."))
        ledger.cash[inst.margin_cash_index].symbol == inst.spec.margin_symbol ||
            throw(AssertionError("Instrument $(inst.spec.symbol) margin cash handle does not match its specification."))
    end
    nothing
end

function _check_history_invariants(acc::Account)
    acc.trade_count >= length(acc.trades) ||
        throw(AssertionError("Stored trade count exceeds the applied fill count."))
    @inbounds for i in 2:length(acc.trades)
        acc.trades[i - 1].tid < acc.trades[i].tid ||
            throw(AssertionError("Stored trade identifiers are not strictly increasing."))
    end
    @inbounds for i in 2:length(acc.cashflows)
        acc.cashflows[i - 1].id < acc.cashflows[i].id ||
            throw(AssertionError("Stored cashflow identifiers are not strictly increasing."))
    end

    cash_count = length(acc.ledger.cash)
    position_count = length(acc.positions)
    @inbounds for cashflow in acc.cashflows
        1 <= cashflow.cash_index <= cash_count ||
            throw(AssertionError("A stored cashflow refers to an unknown cash index."))
        0 <= cashflow.inst_index <= position_count ||
            throw(AssertionError("A stored cashflow refers to an unknown instrument index."))
    end
    nothing
end

function _check_event_state_invariants(acc::Account, atol::Real, rtol::Real)
    state = acc._event_state
    n = length(acc.positions)
    length(state.borrow_amounts) == n || throw(AssertionError("Borrow-fee buffer has a stale size."))
    length(state.fx_effects) == n || throw(AssertionError("FX buffer has a stale size."))
    expected_shorts = Int[]
    expected_borrow = Int[]
    expected_expiries = Int[]
    proceeds = zeros(Price, length(acc.ledger.cash))

    for pos in acc.positions
        spec = pos.inst.spec
        if pos.quantity < 0.0 && spec.contract_kind == ContractKind.Spot && spec.settlement == SettlementStyle.PrincipalExchange
            push!(expected_shorts, pos.index)
            spec.short_borrow_rate > 0.0 && push!(expected_borrow, pos.index)
            proceeds[pos.inst.settle_cash_index] += max(0.0, -pos.quantity * pos.avg_entry_price_settle * spec.multiplier)
        end
        if pos.quantity != 0.0 && (spec.contract_kind == ContractKind.Future || spec.contract_kind == ContractKind.Option)
            push!(expected_expiries, pos.index)
        end
    end

    sort!(expected_expiries; by=idx -> (acc.positions[idx].inst.spec.expiry, idx))
    state.short_positions == expected_shorts || throw(AssertionError("Short-position index is stale."))
    state.borrow_positions == expected_borrow || throw(AssertionError("Borrow-position index is stale."))
    state.expiry_positions == expected_expiries || throw(AssertionError("Expiry-position index is stale."))
    if !state.short_proceeds_dirty
        isapprox(acc.ledger.short_proceeds_by_cash_buffer, proceeds; atol=atol, rtol=rtol) ||
            throw(AssertionError("Short-proceeds cache is stale."))
    end
    nothing
end

"""
    check_invariants(acc; atol=1e-9, rtol=1e-9)

Assert internal account invariants by recomputing derived vectors and
validating registries, ledger numerics, per-position settlement/pricing state,
flat-position resets, and history ordering.
Throws an `AssertionError` on the first violation and returns `true`
otherwise.
"""
function check_invariants(acc::Account; atol::Real=1e-9, rtol::Real=1e-9)
    isfinite(atol) && atol >= 0 || throw(ArgumentError("atol must be non-negative and finite."))
    isfinite(rtol) && rtol >= 0 || throw(ArgumentError("rtol must be non-negative and finite."))
    _check_registry_invariants(acc)
    _check_event_state_invariants(acc, atol, rtol)
    expected_init_by_pos, expected_maint_by_pos = _recompute_margin_by_position(acc)
    @inbounds for (position_index, pos) in pairs(acc.positions)
        inst = pos.inst

        inst.quote_cash_index > 0 || throw(AssertionError("Instrument $(inst.spec.symbol) has unset quote_cash_index."))
        inst.settle_cash_index > 0 || throw(AssertionError("Instrument $(inst.spec.symbol) has unset settle_cash_index."))
        inst.margin_cash_index > 0 || throw(AssertionError("Instrument $(inst.spec.symbol) has unset margin_cash_index."))
        pos.index == inst.index || throw(AssertionError("Position index $(pos.index) must equal instrument index $(inst.index) for $(inst.spec.symbol)."))
        isfinite(pos.entry_commission_quote_carry) || throw(AssertionError("Position $(inst.spec.symbol) must have finite entry_commission_quote_carry."))
        isfinite(pos.variation_margin_pnl_settle_carry) || throw(AssertionError("Position $(inst.spec.symbol) must have finite variation_margin_pnl_settle_carry."))
        isfinite(pos.pending_split_factor) && pos.pending_split_factor > 0.0 ||
            throw(AssertionError("Position $(inst.spec.symbol) must have positive finite pending_split_factor."))
        for (name, value) in (
            ("avg_entry_price", pos.avg_entry_price),
            ("avg_entry_price_settle", pos.avg_entry_price_settle),
            ("avg_settle_price", pos.avg_settle_price),
            ("quantity", pos.quantity),
            ("pnl_quote", pos.pnl_quote),
            ("pnl_settle", pos.pnl_settle),
            ("value_quote", pos.value_quote),
            ("value_settle", pos.value_settle),
            ("init_margin_settle", pos.init_margin_settle),
            ("maint_margin_settle", pos.maint_margin_settle),
        )
            isfinite(value) || throw(AssertionError("Position $(inst.spec.symbol) must have finite $(name)."))
        end
        isapprox(pos.init_margin_settle, expected_init_by_pos[position_index]; atol=atol, rtol=rtol) ||
            throw(AssertionError("Position $(inst.spec.symbol) initial margin cache is stale."))
        isapprox(pos.maint_margin_settle, expected_maint_by_pos[position_index]; atol=atol, rtol=rtol) ||
            throw(AssertionError("Position $(inst.spec.symbol) maintenance margin cache is stale."))
        pos.init_margin_settle >= -atol && pos.maint_margin_settle >= -atol ||
            throw(AssertionError("Position $(inst.spec.symbol) must not have negative margin."))

        if pos.quantity != 0.0
            isfinite(pos.mark_price) || throw(AssertionError("Position $(inst.spec.symbol) must have a finite mark_price when exposure is non-zero."))
            isfinite(pos.last_bid) || throw(AssertionError("Position $(inst.spec.symbol) must have a finite last_bid when exposure is non-zero."))
            isfinite(pos.last_ask) || throw(AssertionError("Position $(inst.spec.symbol) must have a finite last_ask when exposure is non-zero."))
            isfinite(pos.last_price) || throw(AssertionError("Position $(inst.spec.symbol) must have a finite last_price when exposure is non-zero."))
            pos.last_bid <= pos.last_ask || throw(AssertionError("Position $(inst.spec.symbol) has crossed cached quotes."))
            pos.mark_time != typeof(pos.mark_time)(0) || throw(AssertionError("Position $(inst.spec.symbol) must have a mark_time when exposure is non-zero."))
        else
            isapprox(pos.avg_entry_price, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Flat position $(inst.spec.symbol) must have zero avg_entry_price."))
            isapprox(pos.avg_entry_price_settle, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Flat position $(inst.spec.symbol) must have zero avg_entry_price_settle."))
            isapprox(pos.avg_settle_price, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Flat position $(inst.spec.symbol) must have zero avg_settle_price."))
            isapprox(pos.entry_commission_quote_carry, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Flat position $(inst.spec.symbol) must have zero entry_commission_quote_carry."))
            isapprox(pos.variation_margin_pnl_settle_carry, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Flat position $(inst.spec.symbol) must have zero variation_margin_pnl_settle_carry."))
            isapprox(pos.value_quote, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Flat position $(inst.spec.symbol) must have zero value_quote."))
            isapprox(pos.value_settle, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Flat position $(inst.spec.symbol) must have zero value_settle."))
            isapprox(pos.pnl_quote, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Flat position $(inst.spec.symbol) must have zero pnl_quote."))
            isapprox(pos.pnl_settle, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Flat position $(inst.spec.symbol) must have zero pnl_settle."))
            isapprox(pos.init_margin_settle, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Flat position $(inst.spec.symbol) must have zero initial margin."))
            isapprox(pos.maint_margin_settle, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Flat position $(inst.spec.symbol) must have zero maintenance margin."))
        end

        if inst.spec.settlement == SettlementStyle.VariationMargin
            isapprox(pos.value_quote, 0.0; atol=atol, rtol=rtol) || throw(AssertionError("Variation-margin position $(inst.spec.symbol) must have zero value_quote."))
            isapprox(pos.value_settle, 0.0; atol=atol, rtol=rtol) || throw(AssertionError("Variation-margin position $(inst.spec.symbol) must have zero value_settle."))
            isapprox(pos.pnl_quote, 0.0; atol=atol, rtol=rtol) || throw(AssertionError("Variation-margin position $(inst.spec.symbol) must have zero pnl_quote."))
            isapprox(pos.pnl_settle, 0.0; atol=atol, rtol=rtol) || throw(AssertionError("Variation-margin position $(inst.spec.symbol) must have zero pnl_settle."))
        else
            isapprox(pos.variation_margin_pnl_settle_carry, 0.0; atol=atol, rtol=rtol) ||
                throw(AssertionError("Principal-exchange position $(inst.spec.symbol) must have zero variation-margin P&L carry."))
            isapprox(pos.avg_settle_price, pos.avg_entry_price; atol=atol, rtol=rtol) ||
                throw(AssertionError("Position $(inst.spec.symbol) avg_settle_price must match avg_entry_price for non-variation settlement."))
            val_quote_expected = pos.quantity == 0.0 ? 0.0 : calc_value_quote(inst, pos.quantity, pos.mark_price)
            isapprox(pos.value_quote, val_quote_expected; atol=atol, rtol=rtol) ||
                throw(AssertionError("Position $(inst.spec.symbol) value_quote cache is stale (expected $(val_quote_expected), found $(pos.value_quote))."))
            val_settle_expected = to_settle(acc, inst, val_quote_expected)
            isapprox(pos.value_settle, val_settle_expected; atol=atol, rtol=rtol) ||
                throw(AssertionError("Position $(inst.spec.symbol) value_settle cache is stale (expected $(val_settle_expected), found $(pos.value_settle))."))
            pnl_quote_expected = pos.quantity == 0.0 ? 0.0 : calc_pnl_quote(inst, pos.quantity, pos.mark_price, pos.avg_settle_price)
            isapprox(pos.pnl_quote, pnl_quote_expected; atol=atol, rtol=rtol) ||
                throw(AssertionError("Position $(inst.spec.symbol) pnl_quote cache is stale (expected $(pnl_quote_expected), found $(pos.pnl_quote))."))
            pnl_settle_expected = pnl_settle_principal_exchange(inst, pos.quantity, pos.value_settle, pos.avg_entry_price_settle)
            isapprox(pos.pnl_settle, pnl_settle_expected; atol=atol, rtol=rtol) ||
                throw(AssertionError("Position $(inst.spec.symbol) pnl_settle cache is stale (expected $(pnl_settle_expected), found $(pos.pnl_settle))."))
        end
    end

    @inbounds for i in eachindex(acc.ledger.cash)
        cash = acc.ledger.cash[i]
        for (name, value) in (
            ("balance", acc.ledger.balances[i]),
            ("equity", acc.ledger.equities[i]),
            ("initial margin", acc.ledger.init_margin_used[i]),
            ("maintenance margin", acc.ledger.maint_margin_used[i]),
            ("short proceeds", acc.ledger.short_proceeds_by_cash_buffer[i]),
        )
            isfinite(value) ||
                throw(AssertionError("Cash $(cash.symbol) $(name) must be finite."))
        end
    end

    equities_recomputed = recompute_equities(acc)
    isapprox(acc.ledger.equities, equities_recomputed; atol=atol, rtol=rtol) ||
        throw(AssertionError("Stored equities do not match recomputed equities."))

    init_recomputed, maint_recomputed = recompute_margins(acc)
    isapprox(acc.ledger.init_margin_used, init_recomputed; atol=atol, rtol=rtol) ||
        throw(AssertionError("Stored init_margin_used does not match recomputed values."))
    isapprox(acc.ledger.maint_margin_used, maint_recomputed; atol=atol, rtol=rtol) ||
        throw(AssertionError("Stored maint_margin_used does not match recomputed values."))

    option_init = zero.(acc.ledger.init_margin_used)
    option_maint = zero.(acc.ledger.maint_margin_used)
    nonoption_init = zero.(acc.ledger.init_margin_used)
    nonoption_maint = zero.(acc.ledger.maint_margin_used)
    @inbounds for pos in acc.positions
        margin_idx = pos.inst.margin_cash_index
        if pos.inst.spec.contract_kind == ContractKind.Option
            option_init[margin_idx] += expected_init_by_pos[pos.index]
            option_maint[margin_idx] += expected_maint_by_pos[pos.index]
        else
            nonoption_init[margin_idx] += expected_init_by_pos[pos.index]
            nonoption_maint[margin_idx] += expected_maint_by_pos[pos.index]
        end
    end
    isapprox(acc.option_init_by_cash, option_init; atol=atol, rtol=rtol) ||
        throw(AssertionError("Cached option_init_by_cash does not match option position margins."))
    isapprox(acc.option_maint_by_cash, option_maint; atol=atol, rtol=rtol) ||
        throw(AssertionError("Cached option_maint_by_cash does not match option position margins."))
    isapprox(acc.ledger.init_margin_used, nonoption_init .+ acc.option_init_by_cash; atol=atol, rtol=rtol) ||
        throw(AssertionError("Stored init_margin_used does not equal non-option margin plus cached option margin."))
    isapprox(acc.ledger.maint_margin_used, nonoption_maint .+ acc.option_maint_by_cash; atol=atol, rtol=rtol) ||
        throw(AssertionError("Stored maint_margin_used does not equal non-option margin plus cached option margin."))

    _check_history_invariants(acc)
    return true
end
