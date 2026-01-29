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

`from_cash_index` and `to_cash_index` refer to cash asset indexes within the account.
The rate is interpreted as `from` → `to` and the reciprocal is implied for `SpotExchangeRates`.
"""
struct FXUpdate
    from_cash_index::Int
    to_cash_index::Int
    rate::Float64
end

"""
    advance_time!(acc, dt; accrue_interest=true, accrue_borrow_fees=true)

Advances the account clock to `dt`, enforcing non-decreasing time.
Accrues interest and short borrow fees once per forward progression.
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
    process_expiries!(acc, dt; commission=0.0, commission_pct=0.0, physical_expiry_policy=PhysicalExpiryPolicy.Close)

Settles expired futures deterministically at `dt` using the stored position mark.
Requires positions to have finite marks.
For physical-delivery contracts, set
`physical_expiry_policy=PhysicalExpiryPolicy.Close` to auto-close or `PhysicalExpiryPolicy.Error` to
refuse synthetic settlement.
"""
function process_expiries!(
    acc::Account{TTime},
    dt::TTime;
    commission::Price=0.0,
    commission_pct::Price=0.0,
    physical_expiry_policy::PhysicalExpiryPolicy.T=PhysicalExpiryPolicy.Close,
) where {TTime<:Dates.AbstractTime}
    trades = Trade{TTime}[]

    @inbounds for pos in acc.positions
        inst = pos.inst
        inst.contract_kind == ContractKind.Future || continue
        is_expired(inst, dt) || continue
        
        if inst.delivery_style == DeliveryStyle.PhysicalDeliver &&
           physical_expiry_policy == PhysicalExpiryPolicy.Error &&
           pos.quantity != 0.0
            throw(ArgumentError("Expiry for $(inst.symbol) requires physical delivery; pass physical_expiry_policy=PhysicalExpiryPolicy.Close to auto-close."))
        end

        trade_or_reason = settle_expiry!(
            acc,
            inst,
            dt;
            settle_price=pos.mark_price,
            commission=commission,
            commission_pct=commission_pct,
            physical_expiry_policy=physical_expiry_policy,
        )
        trade_or_reason === nothing && continue
        if trade_or_reason isa Trade
            push!(trades, trade_or_reason)
        elseif trade_or_reason isa OrderRejectReason.T
            throw(ArgumentError("Expiry settlement rejected for $(pos.inst.symbol) with reason $(trade_or_reason)"))
        end
    end

    trades
end

"""
Revalue cached settlement amounts after FX updates without touching marks or balances.

Adjusts position `value_settle`/`pnl_settle` for non-VM instruments and updates
margin usage for percent-notional instruments using the latest stored last prices.
"""
@inline function _revalue_fx_caches!(acc::Account)
    @inbounds for pos in acc.positions
        inst = pos.inst
        inst.quote_cash_index == inst.settle_cash_index && continue

        if inst.settlement != SettlementStyle.VariationMargin
            val_quote = pos.value_quote
            new_value_settle = val_quote == 0.0 ? 0.0 : to_settle(acc, inst, val_quote)
            value_delta = new_value_settle - pos.value_settle
            if value_delta != 0.0
                acc.equities[inst.settle_cash_index] += value_delta
            end
            pos.value_settle = new_value_settle

            pnl_quote_val = pos.pnl_quote
            pos.pnl_settle = pnl_quote_val == 0.0 ? 0.0 : to_settle(acc, inst, pnl_quote_val)
        end

        if inst.margin_mode == MarginMode.PercentNotional && pos.quantity != 0.0
            last_price = pos.last_price
            new_init_margin = margin_init_settle(acc, inst, pos.quantity, last_price)
            new_maint_margin = margin_maint_settle(acc, inst, pos.quantity, last_price)
            init_delta = new_init_margin - pos.init_margin_settle
            maint_delta = new_maint_margin - pos.maint_margin_settle
            if init_delta != 0.0
                acc.init_margin_used[inst.settle_cash_index] += init_delta
            end
            if maint_delta != 0.0
                acc.maint_margin_used[inst.settle_cash_index] += maint_delta
            end
            pos.init_margin_settle = new_init_margin
            pos.maint_margin_settle = new_maint_margin
        end
    end
    acc
end

"""
    process_step!(acc, dt; fx_updates=nothing, marks=nothing, funding=nothing, expiries=true, physical_expiry_policy=PhysicalExpiryPolicy.Close, liquidate=false, ...)

Single-step event driver that advances time, updates FX, marks positions, applies funding,
handles expiries, and optionally liquidates to maintenance if required.

Ordering:
1. Enforce non-decreasing time
2. Apply FX updates
3. Apply mark updates (`update_marks!`)
4. Apply funding updates (`apply_funding!`)
5. Accrue interest then borrow fees (`accrue_interest!`, `accrue_borrow_fees!`)
6. Process expiries (`process_expiries!`)
7. Optional maintenance liquidation (runs after expiry/margin release)
8. Stamp `last_event_dt`
"""
function process_step!(
    acc::Account{TTime},
    dt::TTime;
    fx_updates::Union{Nothing,Vector{FXUpdate}}=nothing,
    marks::Union{Nothing,Vector{MarkUpdate}}=nothing,
    funding::Union{Nothing,Vector{FundingUpdate}}=nothing,
    expiries::Bool=true,
    physical_expiry_policy::PhysicalExpiryPolicy.T=PhysicalExpiryPolicy.Close,
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

    if fx_updates !== nothing
        er = acc.exchange_rates
        er isa SpotExchangeRates || throw(ArgumentError("FX updates require SpotExchangeRates on the account."))
        @inbounds for fx in fx_updates
            from_cash = acc.cash[fx.from_cash_index]
            to_cash = acc.cash[fx.to_cash_index]
            update_rate!(er, from_cash, to_cash, fx.rate)
        end
        isempty(fx_updates) || _revalue_fx_caches!(acc)
    end

    if marks !== nothing
        @inbounds for m in marks
            inst = acc.positions[m.inst_index].inst
            update_marks!(acc, inst, dt, m.bid, m.ask, m.last)
        end
    end

    if funding !== nothing
        @inbounds for f in funding
            inst = acc.positions[f.inst_index].inst
            apply_funding!(acc, inst, dt; funding_rate=f.rate)
        end
    end

    accrue_interest && accrue_interest!(acc, dt)
    accrue_borrow_fees && accrue_borrow_fees!(acc, dt)

    expiries && process_expiries!(
        acc,
        dt;
        commission=commission,
        commission_pct=commission_pct,
        physical_expiry_policy=physical_expiry_policy,
    )

    if liquidate && is_under_maintenance(acc)
        liquidate_to_maintenance!(acc, dt; commission=commission, commission_pct=commission_pct, max_steps=max_liq_steps)
    end

    acc.last_event_dt = dt

    acc
end
