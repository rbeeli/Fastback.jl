struct FillPlan
    fill_qty::Quantity
    remaining_qty::Quantity
    commission_quote::Price
    realized_commission_quote::Price   # quote-ccy commission attributed to realized leg (entry allocated + exit-side share)
    commission_settle::Price
    cash_delta_settle::Price
    fill_pnl_settle::Price            # gross additive fill P&L in settlement ccy (excludes commissions)
    realized_qty::Quantity
    new_entry_commission_quote_carry::Price # residual quote-ccy entry commission attached to the post-fill open exposure
    new_qty::Quantity
    new_avg_entry_price_quote::Price
    new_avg_entry_price_settle::Price
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

"""
Compute the fill impact on cash, equity, P&L, and margins without mutating state.
"""
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
    pos_avg_entry_price_settle = pos.avg_entry_price_settle
    pos_avg_settle_price = pos.avg_settle_price
    pos_entry_commission_quote_carry = pos.entry_commission_quote_carry
    inc_qty = calc_exposure_increase_quantity(pos_qty, fill_qty)

    # Percentage commissions should be based on absolute traded notional,
    # including contracts that can trade at negative prices.
    notional_value_quote = abs(fill_price) * abs(fill_qty) * inst.multiplier
    commission_total_quote = commission + commission_pct * notional_value_quote

    fill_price_settle = to_settle(acc, inst, fill_price)

    realized_qty = calc_realized_qty(pos_qty, fill_qty)
    realized_pnl_reduce_quote = realized_qty != 0.0 ?
        calc_pnl_quote(inst, realized_qty, fill_price, pos_avg_settle_price) :
        0.0
    fill_qty_abs = abs(fill_qty)
    realized_qty_abs = abs(realized_qty)
    inc_qty_abs = abs(inc_qty)
    realized_commission_from_fill_quote = fill_qty_abs != 0.0 ?
        commission_total_quote * (realized_qty_abs / fill_qty_abs) :
        0.0
    open_commission_from_fill_quote = fill_qty_abs != 0.0 ?
        commission_total_quote * (inc_qty_abs / fill_qty_abs) :
        0.0
    allocated_entry_commission_quote = (realized_qty_abs != 0.0 && pos_qty != 0.0) ?
        pos_entry_commission_quote_carry * (realized_qty_abs / abs(pos_qty)) :
        0.0
    realized_commission_quote = allocated_entry_commission_quote + realized_commission_from_fill_quote

    commission_settle = to_settle(acc, inst, commission_total_quote)

    if inst.settlement == SettlementStyle.PrincipalExchange
        # Principal-exchange settlement exchanges full principal, so realized settle P&L must use
        # settlement-entry basis (captures FX translation between entry and exit).
        fill_pnl_settle = realized_qty != 0.0 ?
            realized_qty * (fill_price_settle - pos_avg_entry_price_settle) * inst.multiplier :
            0.0
    else
        fill_pnl_quote = cash_delta_quote_vm(
            inst,
            inc_qty,
            realized_pnl_reduce_quote,
            mark_price,
            fill_price,
            0.0,
        )
        fill_pnl_settle = to_settle(acc, inst, fill_pnl_quote)
    end

    cash_delta_quote_val = if inst.settlement == SettlementStyle.VariationMargin
        cash_delta_quote_vm(
            inst,
            inc_qty,
            realized_pnl_reduce_quote,
            mark_price,
            fill_price,
            commission_total_quote,
        )
    else
        cash_delta_quote_principal_exchange(inst, fill_qty, fill_price, commission_total_quote)
    end

    cash_delta_settle = to_settle(acc, inst, cash_delta_quote_val)

    new_qty = pos_qty + fill_qty
    new_entry_commission_quote_carry = if new_qty == 0.0
        0.0
    else
        max(0.0, pos_entry_commission_quote_carry -
                 allocated_entry_commission_quote +
                 open_commission_from_fill_quote)
    end
    new_avg_entry_price_quote = if new_qty == 0.0
        zero(Price)
    elseif sign(new_qty) != sign(pos_qty)
        fill_price
    elseif abs(new_qty) > abs(pos_qty)
        (pos_avg_entry_price * pos_qty + fill_price * fill_qty) / new_qty
    else
        pos_avg_entry_price
    end

    new_avg_entry_price_settle = if new_qty == 0.0
        zero(Price)
    elseif sign(new_qty) != sign(pos_qty)
        fill_price_settle
    elseif abs(new_qty) > abs(pos_qty)
        (pos_avg_entry_price_settle * pos_qty + fill_price_settle * fill_qty) / new_qty
    else
        pos_avg_entry_price_settle
    end

    new_avg_settle_price = if new_qty == 0.0
        zero(Price)
    elseif inst.settlement == SettlementStyle.VariationMargin
        mark_price
    else
        if pos_qty == 0.0
            new_avg_entry_price_quote
        elseif sign(pos_qty) != sign(new_qty)
            fill_price
        elseif abs(new_qty) > abs(pos_qty)
            new_avg_entry_price_quote
        else
            pos_avg_settle_price
        end
    end

    if inst.settlement == SettlementStyle.VariationMargin
        new_pnl_quote = 0.0
        new_value_quote = 0.0
    else
        basis_after = new_avg_entry_price_quote
        new_pnl_quote = calc_pnl_quote(inst, new_qty, mark_price, basis_after)
        new_value_quote = calc_value_quote(inst, new_qty, mark_price)
    end
    new_value_settle = inst.settlement == SettlementStyle.VariationMargin ? 0.0 : to_settle(acc, inst, new_value_quote)
    value_delta_settle = new_value_settle - pos_value_settle

    new_pnl_settle = if inst.settlement == SettlementStyle.VariationMargin
        0.0
    else
        pnl_settle_principal_exchange(inst, new_qty, new_value_settle, new_avg_entry_price_settle)
    end

    new_init_margin_settle = margin_init_margin_ccy(acc, inst, new_qty, margin_price)
    new_maint_margin_settle = margin_maint_margin_ccy(acc, inst, new_qty, margin_price)
    init_margin_delta = new_init_margin_settle - pos_init_margin
    maint_margin_delta = new_maint_margin_settle - pos_maint_margin

    FillPlan(
        fill_qty,
        remaining_qty,
        commission_total_quote,
        realized_commission_quote,
        commission_settle,
        cash_delta_settle,
        fill_pnl_settle,
        realized_qty,
        new_entry_commission_quote_carry,
        new_qty,
        new_avg_entry_price_quote,
        new_avg_entry_price_settle,
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
