struct FillPlan
    fill_qty::Quantity
    remaining_qty::Quantity
    commission::Price
    cash_delta::Price
    realized_pnl_entry_quote::Price
    realized_pnl_settle_quote::Price  # settle-basis PnL, still in quote ccy (used for VM cash)
    realized_pnl_entry::Price         # entry-basis realized P&L in settlement currency (gross, excludes commissions)
    realized_pnl_settle::Price        # settlement-basis realized P&L in settlement currency (gross, excludes commissions)
    realized_qty::Quantity
    new_qty::Quantity
    new_avg_entry_price::Price
    new_avg_settle_price::Price
    new_value_quote::Price
    new_value_settle::Price
    new_pnl_quote::Price
    new_pnl_settle::Price
    new_init_margin_settle::Price
    new_maint_margin_settle::Price
    value_delta_settle::Price
    init_margin_delta::Price
    maint_margin_delta::Price
end

@inline function plan_fill(
    acc::Account{TTime},
    pos::Position{TTime},
    order::Order{TTime},
    dt::TTime,
    fill_price::Price,
    mark_price::Price,
    margin_price::Price,
    fill_qty::Quantity,
    commission::Price,
    commission_pct::Price,
) where {TTime<:Dates.AbstractTime}
    inst = order.inst

    # set fill quantity if not provided
    fill_qty = fill_qty != 0 ? fill_qty : order.quantity
    remaining_qty = order.quantity - fill_qty
    pos_qty = pos.quantity
    pos_value_quote = pos.value_quote
    pos_value_settle = pos.value_settle
    pos_init_margin = pos.init_margin_settle
    pos_maint_margin = pos.maint_margin_settle
    pos_avg_entry_price = pos.avg_entry_price
    pos_avg_settle_price = pos.avg_settle_price
    inc_qty = calc_exposure_increase_quantity(pos_qty, fill_qty)

    nominal_value_quote = fill_price * abs(fill_qty) * inst.multiplier
    commission_total_quote = commission + commission_pct * nominal_value_quote

    realized_qty = calc_realized_qty(pos_qty, fill_qty)
    realized_pnl_entry_quote = realized_qty != 0.0 ?
        pnl_quote(inst, realized_qty, fill_price, pos_avg_entry_price) :
        0.0
    realized_pnl_settle_quote = realized_qty != 0.0 ?
        pnl_quote(inst, realized_qty, fill_price, pos_avg_settle_price) :
        0.0

    commission_settle = to_settle(acc, inst, commission_total_quote)

    realized_pnl_entry = to_settle(acc, inst, realized_pnl_entry_quote)
    realized_pnl_settle = to_settle(acc, inst, realized_pnl_settle_quote)

    cash_delta_quote_val = if inst.settlement == SettlementStyle.VariationMargin
        open_settle_quote = pnl_quote(inst, inc_qty, mark_price, fill_price)
        open_settle_quote + realized_pnl_settle_quote - commission_total_quote
    else
        cash_pnl_quote = realized_pnl_entry_quote
        cash_delta_quote(
            inst,
            fill_qty,
            fill_price,
            commission_total_quote;
            realized_pnl_quote=cash_pnl_quote,
        )
    end

    cash_delta = to_settle(acc, inst, cash_delta_quote_val)

    new_qty = pos_qty + fill_qty
    new_avg_entry_price = if new_qty == 0.0
        zero(Price)
    elseif sign(new_qty) != sign(pos_qty)
        fill_price
    elseif abs(new_qty) > abs(pos_qty)
        (pos_avg_entry_price * pos_qty + fill_price * fill_qty) / new_qty
    else
        pos_avg_entry_price
    end

    new_avg_settle_price = if new_qty == 0.0
        zero(Price)
    elseif inst.settlement == SettlementStyle.VariationMargin
        mark_price
    else
        if pos_qty == 0.0
            new_avg_entry_price
        elseif sign(pos_qty) != sign(new_qty)
            fill_price
        elseif abs(new_qty) > abs(pos_qty)
            new_avg_entry_price
        else
            pos_avg_settle_price
        end
    end

    if inst.settlement == SettlementStyle.VariationMargin
        new_pnl_quote = 0.0
        new_value_quote = 0.0
    else
        basis_after = new_avg_entry_price
        new_pnl_quote = pnl_quote(inst, new_qty, mark_price, basis_after)
        new_value_quote = value_quote(inst, new_qty, mark_price, basis_after)
    end
    new_value_settle = inst.settlement == SettlementStyle.VariationMargin ? 0.0 : to_settle(acc, inst, new_value_quote)
    value_delta_settle = new_value_settle - pos_value_settle

    new_pnl_settle = inst.settlement == SettlementStyle.VariationMargin ? 0.0 : to_settle(acc, inst, new_pnl_quote)

    new_init_margin_settle = margin_init_settle(acc, inst, new_qty, margin_price)
    new_maint_margin_settle = margin_maint_settle(acc, inst, new_qty, margin_price)
    init_margin_delta = new_init_margin_settle - pos_init_margin
    maint_margin_delta = new_maint_margin_settle - pos_maint_margin

    return FillPlan(
        fill_qty,
        remaining_qty,
        commission_settle,
        cash_delta,
        realized_pnl_entry_quote,
        realized_pnl_settle_quote,
        realized_pnl_entry,
        realized_pnl_settle,
        realized_qty,
        new_qty,
        new_avg_entry_price,
        new_avg_settle_price,
        new_value_quote,
        new_value_settle,
        new_pnl_quote,
        new_pnl_settle,
        new_init_margin_settle,
        new_maint_margin_settle,
        value_delta_settle,
        init_margin_delta,
        maint_margin_delta,
    )
end
