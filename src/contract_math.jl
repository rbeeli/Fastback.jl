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
@inline function value_quote(inst::Instrument, qty, price, basis_price)::Price
    settlement = inst.settlement
    if settlement == SettlementStyle.Asset
        return qty * price * inst.multiplier
    elseif settlement == SettlementStyle.Cash
        return pnl_quote(inst, qty, price, basis_price)
    elseif settlement == SettlementStyle.VariationMargin
        return zero(Price)
    else
        throw(ArgumentError("Unsupported settlement style $(inst.settlement)."))
    end
end

"""
Quote-currency cash delta for a fill, honoring settlement style.
"""
@inline function cash_delta_quote(
    inst::Instrument,
    fill_qty,
    fill_price,
    commission_total_quote;
    realized_pnl_quote::Price=0.0,
)::Price
    settlement = inst.settlement
    if settlement == SettlementStyle.Asset
        return -(fill_price * fill_qty * inst.multiplier) - commission_total_quote
    elseif settlement == SettlementStyle.Cash
        return realized_pnl_quote - commission_total_quote
    elseif settlement == SettlementStyle.VariationMargin
        return realized_pnl_quote - commission_total_quote
    else
        throw(ArgumentError("Unsupported settlement style $(inst.settlement)."))
    end
end

"""
Calculates the initial margin requirement in the instrument margin currency.
"""
@inline function margin_init_margin_ccy(acc::Account, inst::Instrument, qty, mark)::Price
    acc.mode == AccountMode.Cash && return zero(Price)
    qty == 0 && return zero(Price)
    mode = inst.margin_mode
    if mode == MarginMode.None
        return zero(Price)
    elseif mode == MarginMode.PercentNotional
        rate = qty > 0 ? inst.margin_init_long : inst.margin_init_short
        quote_req = abs(qty) * mark * inst.multiplier * rate
        return to_margin(acc, inst, quote_req)
    elseif mode == MarginMode.FixedPerContract
        per_contract = qty > 0 ? inst.margin_init_long : inst.margin_init_short
        return abs(qty) * per_contract
    end
    throw(ArgumentError("Unsupported margin_mode $(mode) for instrument $(inst.symbol)."))
end

"""
Calculates the maintenance margin requirement in the instrument margin currency.
"""
@inline function margin_maint_margin_ccy(acc::Account, inst::Instrument, qty, mark)::Price
    acc.mode == AccountMode.Cash && return zero(Price)
    qty == 0 && return zero(Price)
    mode = inst.margin_mode
    if mode == MarginMode.None
        return zero(Price)
    elseif mode == MarginMode.PercentNotional
        rate = qty > 0 ? inst.margin_maint_long : inst.margin_maint_short
        quote_req = abs(qty) * mark * inst.multiplier * rate
        return to_margin(acc, inst, quote_req)
    elseif mode == MarginMode.FixedPerContract
        per_contract = qty > 0 ? inst.margin_maint_long : inst.margin_maint_short
        return abs(qty) * per_contract
    end
    throw(ArgumentError("Unsupported margin_mode $(mode) for instrument $(inst.symbol)."))
end
