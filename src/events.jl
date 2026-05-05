using Dates

"""
Typed mark update for `process_step!`.

`inst_index` refers to the instrument index within the account (set during `register_instrument!`).
`bid`/`ask` drive liquidation-aware valuation; `last` is used for margin.
"""
struct MarkUpdate
    inst_index::Int
    bid::Price
    ask::Price
    last::Price
end

"""
Typed underlying mark update for option margin and expiry settlement.

`underlying_symbol` and `quote_symbol` identify the option chain.
`underlying_price` is the underlying spot/reference price in the option quote currency.
"""
struct OptionUnderlyingUpdate
    underlying_symbol::Symbol
    quote_symbol::Symbol
    underlying_price::Price
end

@inline OptionUnderlyingUpdate(inst::Instrument, underlying_price::Real) =
    OptionUnderlyingUpdate(inst.spec.underlying_symbol, inst.spec.quote_symbol, Price(underlying_price))

"""
Typed funding update for `process_step!`.

`inst_index` refers to the instrument index within the account (set during `register_instrument!`).
`rate` is the funding rate applied for the step (positive -> longs pay shorts).
"""
struct FundingUpdate
    inst_index::Int
    rate::Price
end

"""
Typed FX rate update for `process_step!`.

`from_cash` and `to_cash` reference account cash assets.
The rate is interpreted as `from` → `to` and the reciprocal is implied for `ExchangeRates`.
"""
struct FXUpdate
    from_cash::Cash
    to_cash::Cash
    rate::Float64
end

"""
    advance_time!(acc, dt; accrue_interest=true, accrue_borrow_fees=true)

Advances the account clock to `dt`, enforcing non-decreasing time.
Accrues interest and short borrow fees once per forward progression.
Borrow-fee clocks are tracked per position and fills align accrual windows
with actual short exposure.
"""
function advance_time!(
    acc::Account{TTime,TBroker},
    dt::TTime;
    accrue_interest::Bool=true,
    accrue_borrow_fees::Bool=true,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    last_dt = acc.last_event_dt
    (last_dt != TTime(0) && dt < last_dt) &&
        throw(ArgumentError("Event datetime $(dt) precedes last event $(last_dt)."))

    accrue_interest && accrue_interest!(acc, dt)
    accrue_borrow_fees && accrue_borrow_fees!(acc, dt)

    acc.last_event_dt = dt
    return acc
end

"""
    _process_expiries_into!(trades, acc, dt)

Settles expired futures at `dt` using final variation-margin settlement and
expired options using cash-settled intrinsic value, then flattens exposure and
releases margin.
Clears and refills `trades`, returning the same vector. This helper is intended
for internal buffered callers.
"""
function _process_expiries_into!(
    trades::Vector{Trade{TTime}},
    acc::Account{TTime,TBroker},
    dt::TTime;
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    empty!(trades)
    recompute_options = false

    @inbounds for pos in acc.positions
        pos.quantity == 0.0 && continue
        inst = pos.inst
        kind = inst.spec.contract_kind
        (kind == ContractKind.Future || kind == ContractKind.Option) || continue
        is_expired(inst, dt) || continue

        trade = if kind == ContractKind.Future
            settle_expiry!(
                acc,
                inst,
                dt,
            )
        else
            recompute_options = true
            _settle_option_expiry!(
                acc,
                inst,
                dt,
                Price(NaN),
                false,
            )
        end
        trade === nothing && continue
        push!(trades, trade)
    end
    recompute_options && recompute_dirty_option_groups!(acc)

    trades
end

"""
    process_expiries!(acc, dt)

Settles expired futures at `dt` using final variation-margin settlement and
expired options using cash-settled intrinsic value, then flattens exposure and
releases margin.
Returns a caller-owned vector of generated expiry trades.
"""
function process_expiries!(
    acc::Account{TTime,TBroker},
    dt::TTime;
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    _process_expiries_into!(Trade{TTime}[], acc, dt)
end

"""
Revalue cached settlement and margin-currency amounts after FX updates without
touching marks or balances.

Adjusts position `value_settle`/`pnl_settle` for non-VM instruments and updates
margin usage for FX-sensitive requirements (percent-notional, and all fully-funded
requirements) using settlement-aware margin reference prices.
"""
@inline function _fx_updates_touch_pair(fx_updates, from_idx::Int, to_idx::Int)::Bool
    from_idx == to_idx && return false
    fx_updates === nothing && return true
    @inbounds for fx in fx_updates
        fx_from = fx.from_cash.index
        fx_to = fx.to_cash.index
        ((fx_from == from_idx && fx_to == to_idx) || (fx_from == to_idx && fx_to == from_idx)) && return true
    end
    false
end

@inline function _revalue_fx_caches!(acc::Account, fx_updates=nothing)
    recompute_options = false
    @inbounds for pos in acc.positions
        inst = pos.inst
        is_option_inst = inst.spec.contract_kind == ContractKind.Option
        quote_idx = inst.quote_cash_index
        settle_idx = inst.settle_cash_index
        margin_idx = inst.margin_cash_index
        if is_option_inst && pos.quantity != 0.0 && _fx_updates_touch_pair(fx_updates, quote_idx, margin_idx)
            recompute_options = true
            mark_option_position_dirty!(acc, inst.index)
        end
        quote_settle_fx = quote_idx != settle_idx
        quote_margin_fx = !is_option_inst && quote_idx != margin_idx
        margin_fx_sensitive = quote_margin_fx && pos.quantity != 0.0 &&
                              (acc.funding == AccountFunding.FullyFunded || inst.spec.margin_requirement == MarginRequirement.PercentNotional)
        quote_settle_fx || margin_fx_sensitive || continue

        if quote_settle_fx && inst.spec.settlement != SettlementStyle.VariationMargin
            val_quote = pos.value_quote
            new_value_settle = val_quote == 0.0 ? 0.0 : to_settle(acc, inst, val_quote)
            value_delta = new_value_settle - pos.value_settle
            if value_delta != 0.0
                acc.ledger.equities[settle_idx] += value_delta
            end
            pos.value_settle = new_value_settle

            pos.pnl_settle = pnl_settle_principal_exchange(inst, pos.quantity, new_value_settle, pos.avg_entry_price_settle)
        end

        if margin_fx_sensitive
            margin_price = margin_reference_price(acc, inst, pos.mark_price, pos.last_price)
            new_init_margin = margin_init_margin_ccy(acc, inst, pos.quantity, margin_price)
            new_maint_margin = margin_maint_margin_ccy(acc, inst, pos.quantity, margin_price)
            init_delta = new_init_margin - pos.init_margin_settle
            maint_delta = new_maint_margin - pos.maint_margin_settle
            if init_delta != 0.0
                acc.ledger.init_margin_used[margin_idx] += init_delta
            end
            if maint_delta != 0.0
                acc.ledger.maint_margin_used[margin_idx] += maint_delta
            end
            pos.init_margin_settle = new_init_margin
            pos.maint_margin_settle = new_maint_margin
        end
    end
    recompute_options && recompute_dirty_option_groups!(acc)
    acc
end

"""
    process_step!(
        acc,
        dt
        ;
        fx_updates=nothing,
        marks=nothing,
        option_underlyings=nothing,
        funding=nothing,
        expiries=true,
        liquidate=false,
        max_liq_steps::Int=10_000,
        accrue_interest::Bool=true,
        accrue_borrow_fees::Bool=true,
    )

Single-step event driver that advances time, updates FX, marks option underlyings,
marks positions, applies funding, handles expiries, and optionally liquidates to
maintenance if required. Expiry final-settles futures at mark, cash-settles
options at intrinsic value, and releases margin without synthetic execution
fills. Liquidation routes issue close-only fills.
Borrow-fee accrual uses per-position clocks; fills also advance/reset those clocks.

Timing convention:
- Interest/borrow-fee accrual runs before new marks and before FX updates.
- Therefore, accrual over `(t_prev, t]` uses the previously stored balances/prices/FX,
  and updates passed for `dt` apply to subsequent valuation windows.

Ordering:
1. Enforce non-decreasing time
2. Accrue interest then borrow fees (`accrue_interest!`, `accrue_borrow_fees!`)
3. Apply FX updates
4. Revalue FX caches (`_revalue_fx_caches!`)
5. Apply option underlying updates (`update_option_underlying_price!`)
6. Apply mark updates (`update_marks!`)
7. Apply funding updates (`apply_funding!`)
8. Process expiries (`process_expiries!`)
9. Optional maintenance liquidation (runs after expiry/margin release)
10. Stamp `last_event_dt`
"""
function process_step!(
    acc::Account{TTime,TBroker},
    dt::TTime;
    fx_updates::Union{Nothing,Vector{FXUpdate}}=nothing,
    marks::Union{Nothing,Vector{MarkUpdate}}=nothing,
    option_underlyings::Union{Nothing,Vector{OptionUnderlyingUpdate}}=nothing,
    funding::Union{Nothing,Vector{FundingUpdate}}=nothing,
    expiries::Bool=true,
    liquidate::Bool=false,
    max_liq_steps::Int=10_000,
    accrue_interest::Bool=true,
    accrue_borrow_fees::Bool=true,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    last_dt = acc.last_event_dt
    (last_dt != TTime(0) && dt < last_dt) &&
        throw(ArgumentError("Event datetime $(dt) precedes last event $(last_dt)."))

    accrue_interest && accrue_interest!(acc, dt)
    accrue_borrow_fees && accrue_borrow_fees!(acc, dt)

    if fx_updates !== nothing
        er = acc.exchange_rates
        @inbounds for fx in fx_updates
            update_rate!(er, fx.from_cash, fx.to_cash, fx.rate)
        end
        isempty(fx_updates) || _revalue_fx_caches!(acc, fx_updates)
    end

    if option_underlyings !== nothing
        @inbounds for u in option_underlyings
            _update_option_underlying_price!(
                acc,
                u.underlying_symbol,
                u.quote_symbol,
                u.underlying_price,
                false,
            )
            mark_option_underlying_dirty!(acc, u.underlying_symbol, u.quote_symbol)
        end
    end

    recompute_options = false
    if marks !== nothing
        @inbounds for m in marks
            pos = acc.positions[m.inst_index]
            is_option_inst = pos.inst.spec.contract_kind == ContractKind.Option
            recompute_options |= is_option_inst
            _update_marks_from_quotes!(
                acc,
                pos,
                dt,
                m.bid,
                m.ask,
                m.last,
                false,
            )
            is_option_inst && pos.quantity != 0.0 && mark_option_position_dirty!(acc, pos.inst.index)
        end
    end
    if recompute_options || (option_underlyings !== nothing && !isempty(option_underlyings))
        recompute_dirty_option_groups!(acc)
    end

    if funding !== nothing
        @inbounds for f in funding
            inst = acc.positions[f.inst_index].inst
            apply_funding!(acc, inst, dt; funding_rate=f.rate)
        end
    end

    expiries && _process_expiries_into!(acc._expiry_trades_buffer, acc, dt)

    if liquidate && is_under_maintenance(acc)
        liquidate_to_maintenance!(acc, dt; max_steps=max_liq_steps)
    end

    acc.last_event_dt = dt

    acc
end
