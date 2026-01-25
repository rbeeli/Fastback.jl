using Dates

"""
Typed mark update for `process_step!`.

`inst_index` refers to the instrument index within the account (set during `register_instrument!`).
"""
struct MarkUpdate
    inst_index::Int
    bid::Price
    ask::Price
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
    process_expiries!(acc, dt; commission=0.0, commission_pct=0.0)

Settles expired futures deterministically at `dt` using the latest mark price.
Throws if a mark is missing (NaN).
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

        isnan(pos.mark_price) && throw(ArgumentError("Cannot settle $(inst.symbol): mark price is NaN at expiry $(dt)."))

        trade_or_reason = settle_expiry!(
            acc,
            inst,
            dt;
            settle_price=pos.mark_price,
            commission=commission,
            commission_pct=commission_pct,
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
    process_step!(acc, dt; fx_updates=nothing, marks=nothing, funding=nothing, expiries=true, liquidate=false, ...)

Single-step event driver that advances time, updates FX, marks positions, applies funding,
handles expiries, and optionally liquidates to maintenance if required.

Ordering:
1. `advance_time!`
2. Apply FX updates
3. Apply mark updates (`update_marks!`)
4. Apply funding updates (`apply_funding!`)
5. Process expiries (`process_expiries!`)
6. Optional maintenance liquidation
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
    advance_time!(acc, dt; accrue_interest=accrue_interest, accrue_borrow_fees=accrue_borrow_fees)

    if fx_updates !== nothing
        er = acc.exchange_rates
        er isa SpotExchangeRates || throw(ArgumentError("FX updates require SpotExchangeRates on the account."))
        @inbounds for fx in fx_updates
            from_cash = acc.cash[fx.from_cash_index]
            to_cash = acc.cash[fx.to_cash_index]
            update_rate!(er, from_cash, to_cash, fx.rate)
        end
    end

    if marks !== nothing
        @inbounds for m in marks
            inst = acc.positions[m.inst_index].inst
            update_marks!(acc, inst; dt=dt, bid=m.bid, ask=m.ask)
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

    acc
end
