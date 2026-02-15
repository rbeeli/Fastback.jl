"""
Pure, settlement-aware contract math helpers shared across fill and valuation paths.
All functions are side-effect free and return `Price`/`Quantity` primitives for easy testing.

Currency and unit semantics used throughout contract math:

- `price`: quote currency per base unit
- `qty`: base units/contracts (signed)
- `*_quote`: denominated in instrument quote currency
- `*_settle`: denominated in instrument settlement currency
- `*_margin_ccy`: denominated in instrument margin currency (defaults to settlement)
- `*_base`: denominated in account base currency
"""

"""
Quote-currency P&L for a position at `price` relative to `basis_price`.
"""
@inline function calc_pnl_quote(inst::Instrument, qty, price, basis_price)::Price
    qty * (price - basis_price) * inst.multiplier
end

"""
Quote-currency position value contribution under the instrument settlement style.
"""
@inline function calc_value_quote(inst::Instrument, qty, price)::Price
    settlement = inst.settlement
    if settlement == SettlementStyle.PrincipalExchange
        return qty * price * inst.multiplier
    elseif settlement == SettlementStyle.VariationMargin
        return zero(Price)
    else
        throw(ArgumentError("Unsupported settlement style $(inst.settlement)."))
    end
end

"""
Settlement-currency unrealized P&L for principal-exchange exposure.

Uses settlement value minus the settlement-entry notional basis so FX translation
of open principal is reflected in unrealized settlement P&L.
"""
@inline function pnl_settle_principal_exchange(
    inst::Instrument,
    qty,
    value_settle::Price,
    avg_entry_price_settle::Price,
)::Price
    qty == 0 && return zero(Price)
    value_settle - qty * avg_entry_price_settle * inst.multiplier
end

"""
Quote-currency cash delta for a principal-exchange fill.
"""
@inline function cash_delta_quote_principal_exchange(
    inst::Instrument,
    fill_qty::Quantity,
    fill_price::Price,
    commission_total_quote::Price,
)::Price
    -(fill_qty * fill_price * inst.multiplier) - commission_total_quote
end

"""
Quote-currency cash delta for a variation-margin fill.
"""
@inline function cash_delta_quote_vm(
    inst::Instrument,
    inc_qty::Quantity,
    realized_pnl_reduce_quote::Price,
    mark_price::Price,
    fill_price::Price,
    commission_total_quote::Price,
)::Price
    open_settle_quote = calc_pnl_quote(inst, inc_qty, mark_price, fill_price)
    open_settle_quote + realized_pnl_reduce_quote - commission_total_quote
end

"""
Return the reference price used for margin requirements.

- `SettlementStyle.VariationMargin`: always uses the mark price so margin checks
  stay aligned with variation-margin settlement and valuation.
- `AccountFunding.FullyFunded`: uses liquidation-aware marks so full-notional requirements
  stay aligned with equity under bid/ask spreads.
- Other margined-account instruments: use last-traded prices to avoid
  side-dependent bias for principal-exchange settlement.
"""
@inline function margin_reference_price(
    acc::Account,
    inst::Instrument,
    mark_price::Price,
    last_price::Price,
)::Price
    if inst.settlement == SettlementStyle.VariationMargin
        return mark_price
    end
    acc.funding == AccountFunding.FullyFunded ? mark_price : last_price
end

"""
Calculates the initial margin requirement in the instrument margin currency.

`AccountFunding.FullyFunded` forces a fully funded requirement (full notional), evaluated
at the caller-provided margin reference price.
"""
@inline function margin_init_margin_ccy(acc::Account, inst::Instrument, qty, price)::Price
    qty == 0 && return zero(Price)
    if acc.funding == AccountFunding.FullyFunded
        quote_req = abs(qty) * abs(price) * inst.multiplier
        return to_margin(acc, inst, quote_req)
    end
    requirement = inst.margin_requirement
    if requirement == MarginRequirement.PercentNotional
        rate = qty > 0 ? inst.margin_init_long : inst.margin_init_short
        quote_req = abs(qty) * abs(price) * inst.multiplier * rate
        return to_margin(acc, inst, quote_req)
    elseif requirement == MarginRequirement.FixedPerContract
        per_contract = qty > 0 ? inst.margin_init_long : inst.margin_init_short
        return abs(qty) * per_contract
    end
    throw(ArgumentError("Unsupported margin_requirement $(requirement) for instrument $(inst.symbol)."))
end

"""
Calculates the maintenance margin requirement in the instrument margin currency.

`AccountFunding.FullyFunded` forces a fully funded requirement (full notional), evaluated
at the caller-provided margin reference price.
"""
@inline function margin_maint_margin_ccy(acc::Account, inst::Instrument, qty, price)::Price
    qty == 0 && return zero(Price)
    if acc.funding == AccountFunding.FullyFunded
        quote_req = abs(qty) * abs(price) * inst.multiplier
        return to_margin(acc, inst, quote_req)
    end
    requirement = inst.margin_requirement
    if requirement == MarginRequirement.PercentNotional
        rate = qty > 0 ? inst.margin_maint_long : inst.margin_maint_short
        quote_req = abs(qty) * abs(price) * inst.multiplier * rate
        return to_margin(acc, inst, quote_req)
    elseif requirement == MarginRequirement.FixedPerContract
        per_contract = qty > 0 ? inst.margin_maint_long : inst.margin_maint_short
        return abs(qty) * per_contract
    end
    throw(ArgumentError("Unsupported margin_requirement $(requirement) for instrument $(inst.symbol)."))
end
