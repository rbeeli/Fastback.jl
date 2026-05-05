struct FillPlan
    fill_qty::Quantity
    remaining_qty::Quantity
    notional_value_quote::Price
    commission_quote::Price
    realized_commission_quote::Price   # quote-ccy commission attributed to realized leg (entry allocated + exit-side share)
    commission_settle::Price
    cash_delta_settle::Price
    fill_pnl_settle::Price            # gross additive fill P&L in settlement ccy (excludes commissions)
    realized_qty::Quantity
    new_entry_commission_quote_carry::Price # residual signed quote-ccy entry commission/rebate attached to post-fill open exposure
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
