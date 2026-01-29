"""
Pure, settlement-aware contract math helpers shared across fill and valuation paths.
All functions are side-effect free and return `Price`/`Quantity` primitives for easy testing.

Currency and unit semantics used throughout contract math:

- `price`: quote currency per base unit
- `qty`: base units/contracts (signed)
- `*_quote`: denominated in instrument quote currency
- `*_settle`: denominated in instrument settlement currency
- `*_base`: denominated in account base currency
"""

@inline function pnl_quote(inst::Instrument, qty, price, basis_price)::Price
    qty * (price - basis_price) * inst.multiplier
end

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

@inline function margin_init_settle(acc::Account, inst::Instrument, qty, mark)::Price
    acc.mode == AccountMode.Cash && return zero(Price)
    quote_req = margin_init_quote(inst, qty, mark)
    inst.margin_mode == MarginMode.FixedPerContract ? quote_req : to_settle(acc, inst, quote_req)
end

@inline function margin_maint_settle(acc::Account, inst::Instrument, qty, mark)::Price
    acc.mode == AccountMode.Cash && return zero(Price)
    quote_req = margin_maint_quote(inst, qty, mark)
    inst.margin_mode == MarginMode.FixedPerContract ? quote_req : to_settle(acc, inst, quote_req)
end
