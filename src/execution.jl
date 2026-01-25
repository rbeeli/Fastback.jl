struct FillImpact
    fill_qty::Quantity
    remaining_qty::Quantity
    commission::Price
    cash_delta::Price
    realized_pnl_gross::Price
    realized_pnl_net::Price
    realized_qty::Quantity
    new_qty::Quantity
    new_avg_entry_price::Price
    new_value_local::Price
    new_pnl_local::Price
    new_init_margin::Price
    new_maint_margin::Price
end

"""
Computes the cash, P&L, and margin impact of filling an order without mutating state.

Assumes the caller already updated marks with `update_marks!(acc, pos; dt, close_price=fill_price)`.
Returns a `FillImpact` describing the resulting position metrics and account deltas.
`cash_delta` is expressed in the instrument settlement currency.
"""
@inline function compute_fill_impact(
    acc::Account{TTime},
    pos::Position{TTime},
    order::Order{TTime},
    dt::TTime,
    fill_price::Price
    ;
    fill_qty::Quantity=0.0,
    commission::Price=0.0,
    commission_pct::Price=0.0,
) where {TTime<:Dates.AbstractTime}
    inst = order.inst

    # set fill quantity if not provided
    fill_qty = fill_qty != 0 ? fill_qty : order.quantity
    remaining_qty = order.quantity - fill_qty
    pos_qty = pos.quantity

    nominal_value = fill_price * abs(fill_qty) * inst.multiplier
    commission_total = commission + commission_pct * nominal_value

    realized_qty = calc_realized_qty(pos_qty, fill_qty)
    realized_pnl_gross_quote = realized_qty != 0.0 ?
        (fill_price - pos.avg_entry_price) * realized_qty * inst.multiplier :
        0.0

    cash_delta_quote = if inst.settlement == SettlementStyle.Asset
        -(fill_price * fill_qty * inst.multiplier) - commission_total
    elseif inst.settlement == SettlementStyle.Cash
        realized_pnl_gross_quote - commission_total
    elseif inst.settlement == SettlementStyle.VariationMargin
        -commission_total
    else
        throw(ArgumentError("Unsupported settlement style $(inst.settlement)."))
    end

    cash_delta = to_settle(acc, inst, cash_delta_quote)
    realized_pnl_gross = to_settle(acc, inst, realized_pnl_gross_quote)
    commission_settle = to_settle(acc, inst, commission_total)

    realized_pnl_net = realized_pnl_gross - commission_settle

    new_qty = pos_qty + fill_qty
    new_avg_entry_price = if new_qty == 0.0
        zero(Price)
    elseif sign(new_qty) != sign(pos_qty)
        fill_price
    elseif abs(new_qty) > abs(pos_qty)
        (pos.avg_entry_price * pos_qty + fill_price * fill_qty) / new_qty
    else
        pos.avg_entry_price
    end

    new_pnl_local = if inst.settlement == SettlementStyle.VariationMargin
        0.0
    else
        new_qty * (fill_price - new_avg_entry_price) * inst.multiplier
    end

    new_value_local = if inst.settlement == SettlementStyle.Asset
        new_qty * fill_price * inst.multiplier
    elseif inst.settlement == SettlementStyle.Cash
        new_pnl_local
    elseif inst.settlement == SettlementStyle.VariationMargin
        0.0
    else
        throw(ArgumentError("Unsupported settlement style $(inst.settlement)."))
    end

    new_init_margin = margin_init_settle(acc, inst, new_qty, fill_price)
    new_maint_margin = margin_maint_settle(acc, inst, new_qty, fill_price)

    return FillImpact(
        fill_qty,
        remaining_qty,
        commission_settle,
        cash_delta,
        realized_pnl_gross,
        realized_pnl_net,
        realized_qty,
        new_qty,
        new_avg_entry_price,
        new_value_local,
        new_pnl_local,
        new_init_margin,
        new_maint_margin,
    )
end
