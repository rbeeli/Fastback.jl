struct FillPlan
    fill_qty::Quantity
    remaining_qty::Quantity
    commission::Price
    cash_delta::Price
    realized_pnl_gross::Price
    realized_pnl_net::Price
    realized_qty::Quantity
    new_qty::Quantity
    new_avg_entry_price::Price
    new_avg_settle_price::Price
    new_value_quote::Price
    new_pnl_quote::Price
    new_init_margin_settle::Price
    new_maint_margin_settle::Price
    value_delta_settle::Price
    init_margin_delta::Price
    maint_margin_delta::Price
end

"""
Plans the cash, P&L, and margin impact of filling an order without mutating state.

Assumes the caller already updated marks with `update_marks!(acc, pos; dt, close_price=fill_price)`.
Returns a `FillPlan` describing the resulting position metrics, account deltas, and
derived margin/value deltas in settlement currency.
`cash_delta` and other settlement values are expressed in the instrument settlement currency.
"""
@inline function plan_fill(
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
    pos_value_quote = pos.value_quote
    pos_init_margin = pos.init_margin_settle
    pos_maint_margin = pos.maint_margin_settle
    pos_avg_settle_price = pos.avg_settle_price

    nominal_value_quote = fill_price * abs(fill_qty) * inst.multiplier
    commission_total_quote = commission + commission_pct * nominal_value_quote

    realized_qty = calc_realized_qty(pos_qty, fill_qty)
    realized_basis = pos.avg_entry_price
    realized_pnl_gross_quote = realized_qty != 0.0 ?
        pnl_quote(inst, realized_qty, fill_price, realized_basis) :
        0.0

    cash_delta_quote_val = cash_delta_quote(
        inst,
        fill_qty,
        fill_price,
        commission_total_quote;
        realized_pnl_quote=realized_pnl_gross_quote,
    )

    cash_delta = to_settle(acc, inst, cash_delta_quote_val)
    realized_pnl_gross = to_settle(acc, inst, realized_pnl_gross_quote)
    commission_settle = to_settle(acc, inst, commission_total_quote)

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

    new_avg_settle_price = if new_qty == 0.0
        zero(Price)
    elseif pos_qty == 0.0
        inst.settlement == SettlementStyle.VariationMargin ? fill_price : new_avg_entry_price
    elseif sign(pos_qty) != sign(new_qty)
        fill_price
    elseif inst.settlement != SettlementStyle.VariationMargin && abs(new_qty) > abs(pos_qty)
        new_avg_entry_price
    else
        pos_avg_settle_price
    end

    basis_after = if inst.settlement == SettlementStyle.VariationMargin
        new_qty == 0.0 ? zero(Price) : fill_price
    else
        new_avg_entry_price
    end

    new_pnl_quote = pnl_quote(inst, new_qty, fill_price, basis_after)
    new_value_quote = value_quote(inst, new_qty, fill_price, basis_after)
    value_delta_settle = to_settle(acc, inst, new_value_quote - pos_value_quote)

    new_init_margin_settle = margin_init_settle(acc, inst, new_qty, fill_price)
    new_maint_margin_settle = margin_maint_settle(acc, inst, new_qty, fill_price)
    init_margin_delta = new_init_margin_settle - pos_init_margin
    maint_margin_delta = new_maint_margin_settle - pos_maint_margin

    return FillPlan(
        fill_qty,
        remaining_qty,
        commission_settle,
        cash_delta,
        realized_pnl_gross,
        realized_pnl_net,
        realized_qty,
        new_qty,
        new_avg_entry_price,
        new_avg_settle_price,
        new_value_quote,
        new_pnl_quote,
        new_init_margin_settle,
        new_maint_margin_settle,
        value_delta_settle,
        init_margin_delta,
        maint_margin_delta,
    )
end
