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
@inline function pnl_quote(inst::Instrument, qty, price, basis_price)::Price
    qty * (price - basis_price) * inst.multiplier
end

"""
Quote-currency position value contribution under the instrument settlement style.
"""
@inline function value_quote(inst::Instrument, qty, price)::Price
    settlement = inst.settlement
    if settlement == SettlementStyle.Asset
        return qty * price * inst.multiplier
    elseif settlement == SettlementStyle.VariationMargin
        return zero(Price)
    else
        throw(ArgumentError("Unsupported settlement style $(inst.settlement)."))
    end
end

"""
Quote-currency cash delta for an asset-settled fill.
"""
@inline function cash_delta_quote_asset(
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
    realized_pnl_settle_quote::Price,
    mark_price::Price,
    fill_price::Price,
    commission_total_quote::Price,
)::Price
    open_settle_quote = pnl_quote(inst, inc_qty, mark_price, fill_price)
    open_settle_quote + realized_pnl_settle_quote - commission_total_quote
end

"""
Calculates the initial margin requirement in the instrument margin currency.

`AccountMode.Cash` forces a fully funded requirement (full notional).
"""
@inline function margin_init_margin_ccy(acc::Account, inst::Instrument, qty, mark)::Price
    qty == 0 && return zero(Price)
    if acc.mode == AccountMode.Cash
        quote_req = abs(qty) * abs(mark) * inst.multiplier
        return to_margin(acc, inst, quote_req)
    end
    mode = inst.margin_mode
    if mode == MarginMode.None
        return zero(Price)
    elseif mode == MarginMode.PercentNotional
        rate = qty > 0 ? inst.margin_init_long : inst.margin_init_short
        quote_req = abs(qty) * abs(mark) * inst.multiplier * rate
        return to_margin(acc, inst, quote_req)
    elseif mode == MarginMode.FixedPerContract
        per_contract = qty > 0 ? inst.margin_init_long : inst.margin_init_short
        return abs(qty) * per_contract
    end
    throw(ArgumentError("Unsupported margin_mode $(mode) for instrument $(inst.symbol)."))
end

"""
Calculates the maintenance margin requirement in the instrument margin currency.

`AccountMode.Cash` forces a fully funded requirement (full notional).
"""
@inline function margin_maint_margin_ccy(acc::Account, inst::Instrument, qty, mark)::Price
    qty == 0 && return zero(Price)
    if acc.mode == AccountMode.Cash
        quote_req = abs(qty) * abs(mark) * inst.multiplier
        return to_margin(acc, inst, quote_req)
    end
    mode = inst.margin_mode
    if mode == MarginMode.None
        return zero(Price)
    elseif mode == MarginMode.PercentNotional
        rate = qty > 0 ? inst.margin_maint_long : inst.margin_maint_short
        quote_req = abs(qty) * abs(mark) * inst.multiplier * rate
        return to_margin(acc, inst, quote_req)
    elseif mode == MarginMode.FixedPerContract
        per_contract = qty > 0 ? inst.margin_maint_long : inst.margin_maint_short
        return abs(qty) * per_contract
    end
    throw(ArgumentError("Unsupported margin_mode $(mode) for instrument $(inst.symbol)."))
end
