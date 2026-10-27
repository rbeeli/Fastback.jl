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

"""
    transfer_spot_positions!(acc, transfers, dt)

Move open principal-exchange spot positions to other instruments without a fill,
as on a ticker change. `transfers` holds `from => to` instrument pairs that apply
at once, so two instruments may swap.

Each successor takes its predecessor's quantity, price bases, commission carry,
pending split factor, valuation, quotes, mark time and borrow-fee clock, and its
margin is recomputed under its own instrument; the predecessor is left flat. A
pair whose predecessor is flat changes nothing. Both instruments of a pair must
be principal-exchange spot instruments in the same quote, settlement and margin
currencies with the same multiplier, and a successor must be flat unless it is
itself a predecessor in `transfers`.

Account cash and equity are unchanged, and no trade or cashflow is recorded, so
holding periods reconstructed from trades give the moved exposure an unknown
entry. Borrow time not yet accrued accrues at the successor's rate; accrue
financing through `dt` first to charge it at the predecessor's. Validation
failures leave the account unchanged; a failure while applying poisons it.
"""
function transfer_spot_positions!(
    acc::Account{TTime},
    transfers::AbstractVector{<:Pair{<:Instrument{TTime},<:Instrument{TTime}}},
    dt::TTime,
) where {TTime<:Dates.AbstractTime}
    _validate_account_timestamp(acc, dt)
    _validate_spot_transfers(acc, transfers, dt)
    moves = Tuple{Position{TTime},Position{TTime}}[]

    try
        for (from, to) in transfers
            source = get_position(acc, from)
            source.quantity == 0.0 && continue
            push!(moves, (get_position(acc, to), _detach_position(source)))
            _vacate_position!(acc, source)
        end

        for (target, carried) in moves
            _occupy_position!(acc, target, carried, dt)
        end

        _advance_account_timestamp!(acc, dt)
        return acc
    catch
        _poison!(acc)
        rethrow()
    end
end

function _validate_spot_transfers(
    acc::Account{TTime},
    transfers::AbstractVector{<:Pair{<:Instrument{TTime},<:Instrument{TTime}}},
    dt::TTime,
) where {TTime<:Dates.AbstractTime}
    sources = Set{Int}()
    targets = Set{Int}()

    for (from, to) in transfers
        get_position(acc, from)
        get_position(acc, to)
        from_spec, to_spec = from.spec, to.spec
        from.index != to.index ||
            throw(ArgumentError("Position of $(from_spec.symbol) cannot transfer to itself."))
        from.index in sources &&
            throw(ArgumentError("Position of $(from_spec.symbol) transfers twice."))
        to.index in targets &&
            throw(ArgumentError("Instrument $(to_spec.symbol) receives two positions."))
        push!(sources, from.index)
        push!(targets, to.index)
        for spec in (from_spec, to_spec)
            spec.contract_kind == ContractKind.Spot &&
                spec.settlement == SettlementStyle.PrincipalExchange ||
                throw(ArgumentError("Position transfers require principal-exchange spot instruments, got $(spec.symbol)."))
        end
        (from.quote_cash_index, from.settle_cash_index, from.margin_cash_index, from_spec.multiplier) ==
            (to.quote_cash_index, to.settle_cash_index, to.margin_cash_index, to_spec.multiplier) ||
            throw(ArgumentError("Position of $(from_spec.symbol) cannot transfer to $(to_spec.symbol) in other currencies or multiplier."))
    end

    for (from, to) in transfers
        source = get_position(acc, from)
        source.quantity == 0.0 && continue
        source.mark_time <= dt ||
            throw(ArgumentError("Transfer datetime $(dt) precedes the last mark $(source.mark_time) of $(from.spec.symbol)."))
        get_position(acc, to).quantity == 0.0 || to.index in sources ||
            throw(ArgumentError("Instrument $(to.spec.symbol) already holds a position."))
    end
    nothing
end

# A copy of the position state that a transfer moves, detached from the account.
function _detach_position(pos::Position{TTime})::Position{TTime} where {TTime<:Dates.AbstractTime}
    Position{TTime}(
        pos.index,
        pos.inst;
        avg_entry_price=pos.avg_entry_price,
        avg_entry_price_settle=pos.avg_entry_price_settle,
        avg_settle_price=pos.avg_settle_price,
        quantity=pos.quantity,
        entry_commission_quote_carry=pos.entry_commission_quote_carry,
        variation_margin_pnl_settle_carry=pos.variation_margin_pnl_settle_carry,
        pending_split_factor=pos.pending_split_factor,
        pnl_quote=pos.pnl_quote,
        pnl_settle=pos.pnl_settle,
        value_quote=pos.value_quote,
        value_settle=pos.value_settle,
        init_margin_settle=pos.init_margin_settle,
        maint_margin_settle=pos.maint_margin_settle,
        mark_price=pos.mark_price,
        last_bid=pos.last_bid,
        last_ask=pos.last_ask,
        last_price=pos.last_price,
        mark_time=pos.mark_time,
        borrow_fee_dt=pos.borrow_fee_dt,
    )
end

# Flatten a position whose state moves to another one; the ledger totals keep its value and margin,
# which its successor takes over.
function _vacate_position!(acc::Account{TTime}, pos::Position{TTime}) where {TTime<:Dates.AbstractTime}
    old_qty = pos.quantity
    pos.avg_entry_price = 0.0
    pos.avg_entry_price_settle = 0.0
    pos.avg_settle_price = 0.0
    pos.quantity = 0.0
    pos.entry_commission_quote_carry = 0.0
    pos.variation_margin_pnl_settle_carry = 0.0
    pos.pending_split_factor = 1.0
    pos.pnl_quote = 0.0
    pos.pnl_settle = 0.0
    pos.value_quote = 0.0
    pos.value_settle = 0.0
    pos.init_margin_settle = 0.0
    pos.maint_margin_settle = 0.0
    pos.borrow_fee_dt = TTime(0)
    _update_position_events!(acc, pos, old_qty)
    nothing
end

# Give a flat position the moved state of `carried` and margin it under its own instrument.
function _occupy_position!(
    acc::Account{TTime},
    pos::Position{TTime},
    carried::Position{TTime},
    dt::TTime,
) where {TTime<:Dates.AbstractTime}
    pos.avg_entry_price = carried.avg_entry_price
    pos.avg_entry_price_settle = carried.avg_entry_price_settle
    pos.avg_settle_price = carried.avg_settle_price
    pos.quantity = carried.quantity
    pos.entry_commission_quote_carry = carried.entry_commission_quote_carry
    pos.variation_margin_pnl_settle_carry = carried.variation_margin_pnl_settle_carry
    pos.pending_split_factor = carried.pending_split_factor
    pos.pnl_quote = carried.pnl_quote
    pos.pnl_settle = carried.pnl_settle
    pos.value_quote = carried.value_quote
    pos.value_settle = carried.value_settle
    pos.init_margin_settle = carried.init_margin_settle
    pos.maint_margin_settle = carried.maint_margin_settle
    pos.mark_price = carried.mark_price
    pos.last_bid = carried.last_bid
    pos.last_ask = carried.last_ask
    pos.last_price = carried.last_price
    pos.mark_time = carried.mark_time
    pos.borrow_fee_dt = if !_borrow_fee_eligible(pos)
        TTime(0)
    elseif _borrow_fee_eligible(carried)
        carried.borrow_fee_dt
    else
        dt
    end
    _update_position_events!(acc, pos, 0.0)
    _update_margin!(acc, pos, margin_reference_price(acc, pos.inst, pos.mark_price, pos.last_price))
    nothing
end
