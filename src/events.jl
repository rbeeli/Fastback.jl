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
The rate is interpreted as `from` → `to` and the reciprocal is implied for `SpotExchangeRates`.
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
    acc::Account{TTime},
    dt::TTime;
    accrue_interest::Bool=true,
    accrue_borrow_fees::Bool=true,
) where {TTime<:Dates.AbstractTime}
    last_dt = acc.last_event_dt
    (last_dt != TTime(0) && dt < last_dt) &&
        throw(ArgumentError("Event datetime $(dt) precedes last event $(last_dt)."))

    accrue_interest && accrue_interest!(acc, dt)
    accrue_borrow_fees && accrue_borrow_fees!(acc, dt)

    acc.last_event_dt = dt
    return acc
end

"""
    process_expiries!(acc, dt; commission=0.0, commission_pct=0.0)

Settles expired futures deterministically at `dt` using the stored position mark.
Requires positions to have finite marks.

Throws `OrderRejectError` if a synthetic expiry close is rejected by risk checks.
"""
function process_expiries!(
    acc::Account{TTime},
    dt::TTime;
    commission::Price=0.0,
    commission_pct::Price=0.0,
) where {TTime<:Dates.AbstractTime}
    trades = Trade{TTime}[]

    @inbounds for pos in acc.positions
        inst = pos.inst
        inst.contract_kind == ContractKind.Future || continue
        is_expired(inst, dt) || continue
        
        trade = settle_expiry!(
            acc,
            inst,
            dt;
            settle_price=pos.mark_price,
            commission=commission,
            commission_pct=commission_pct,
        )
        trade === nothing && continue
        push!(trades, trade)
    end

    trades
end

"""
Revalue cached settlement and margin-currency amounts after FX updates without
touching marks or balances.

Adjusts position `value_settle`/`pnl_settle` for non-VM instruments and updates
margin usage for percent-notional instruments using the latest stored last prices.
"""
@inline function _revalue_fx_caches!(acc::Account)
    @inbounds for pos in acc.positions
        inst = pos.inst
        quote_idx = inst.quote_cash_index
        settle_idx = inst.settle_cash_index
        margin_idx = inst.margin_cash_index
        quote_settle_fx = quote_idx != settle_idx
        quote_margin_fx = quote_idx != margin_idx
        quote_settle_fx || (inst.margin_mode == MarginMode.PercentNotional && quote_margin_fx) || continue

        if quote_settle_fx && inst.settlement != SettlementStyle.VariationMargin
            val_quote = pos.value_quote
            new_value_settle = val_quote == 0.0 ? 0.0 : to_settle(acc, inst, val_quote)
            value_delta = new_value_settle - pos.value_settle
            if value_delta != 0.0
                acc.ledger.equities[settle_idx] += value_delta
            end
            pos.value_settle = new_value_settle

            pnl_quote_val = pos.pnl_quote
            pos.pnl_settle = pnl_quote_val == 0.0 ? 0.0 : to_settle(acc, inst, pnl_quote_val)
        end

        if inst.margin_mode == MarginMode.PercentNotional && pos.quantity != 0.0 && quote_margin_fx
            last_price = pos.last_price
            new_init_margin = margin_init_margin_ccy(acc, inst, pos.quantity, last_price)
            new_maint_margin = margin_maint_margin_ccy(acc, inst, pos.quantity, last_price)
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
    acc
end

"""
    process_step!(
        acc,
        dt
        ;
        fx_updates=nothing,
        marks=nothing,
        funding=nothing,
        expiries=true,
        liquidate=false,
        commission::Price=0.0,
        commission_pct::Price=0.0,
        max_liq_steps::Int=10_000,
        accrue_interest::Bool=true,
        accrue_borrow_fees::Bool=true,
    )

Single-step event driver that advances time, updates FX, marks positions, applies funding,
handles expiries, and optionally liquidates to maintenance if required.

Throws `OrderRejectError` if expiry settlement or liquidation fills are rejected by risk checks.
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
5. Apply mark updates (`update_marks!`)
6. Apply funding updates (`apply_funding!`)
7. Process expiries (`process_expiries!`)
8. Optional maintenance liquidation (runs after expiry/margin release)
9. Stamp `last_event_dt`
"""
function process_step!(
    acc::Account{TTime},
    dt::TTime;
    fx_updates::Union{Nothing,Vector{FXUpdate}}=nothing,
    marks::Union{Nothing,Vector{MarkUpdate}}=nothing,
    funding::Union{Nothing,Vector{FundingUpdate}}=nothing,
    expiries::Bool=true,
    liquidate::Bool=false,
    commission::Price=0.0,
    commission_pct::Price=0.0,
    max_liq_steps::Int=10_000,
    accrue_interest::Bool=true,
    accrue_borrow_fees::Bool=true,
) where {TTime<:Dates.AbstractTime}
    last_dt = acc.last_event_dt
    (last_dt != TTime(0) && dt < last_dt) &&
        throw(ArgumentError("Event datetime $(dt) precedes last event $(last_dt)."))

    accrue_interest && accrue_interest!(acc, dt)
    accrue_borrow_fees && accrue_borrow_fees!(acc, dt)

    if fx_updates !== nothing
        er = acc.exchange_rates
        er isa SpotExchangeRates || throw(ArgumentError("FX updates require SpotExchangeRates on the account."))
        @inbounds for fx in fx_updates
            update_rate!(er, fx.from_cash, fx.to_cash, fx.rate)
        end
        isempty(fx_updates) || _revalue_fx_caches!(acc)
    end

    if marks !== nothing
        @inbounds for m in marks
            pos = acc.positions[m.inst_index]
            update_marks!(acc, pos, dt, m.bid, m.ask, m.last)
        end
    end

    if funding !== nothing
        @inbounds for f in funding
            inst = acc.positions[f.inst_index].inst
            apply_funding!(acc, inst, dt; funding_rate=f.rate)
        end
    end

    expiries && process_expiries!(
        acc,
        dt;
        commission=commission,
        commission_pct=commission_pct,
    )

    if liquidate && is_under_maintenance(acc)
        liquidate_to_maintenance!(acc, dt; commission=commission, commission_pct=commission_pct, max_steps=max_liq_steps)
    end

    acc.last_event_dt = dt

    acc
end
