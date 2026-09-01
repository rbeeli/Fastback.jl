struct FillPlan
    fill_qty::Quantity
    remaining_qty::Quantity
    notional_value_quote::Price
    notional_value_base::Price
    commission_quote::Price
    realized_commission_quote::Price   # quote-ccy commission attributed to realized leg (entry allocated + exit-side share)
    commission_settle::Price
    cash_delta_settle::Price
    balance_delta_settle::Price        # complete transition, including mark settlement and borrow fees
    equity_delta_settle::Price         # complete transition, including mark/value changes and borrow fees
    variation_margin_settle::Price
    borrow_fee_settle::Price
    fill_pnl_settle::Price            # gross additive fill P&L in settlement ccy (excludes commissions)
    realized_qty::Quantity
    new_entry_commission_quote_carry::Price # residual signed quote-ccy entry commission/rebate attached to post-fill open exposure
    new_variation_margin_pnl_settle_carry::Price # residual settled VM P&L attached to post-fill open exposure
    preceding_split_factor::Float64
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
Immutable accounting state consumed by fill planning.

Keeping this as a compact value type lets ordinary fills stage a marked position
without allocating or mutating the live `Position` before risk validation succeeds.
"""
struct _FillPositionState
    quantity::Quantity
    avg_entry_price::Price
    avg_entry_price_settle::Price
    avg_settle_price::Price
    entry_commission_quote_carry::Price
    variation_margin_pnl_settle_carry::Price
    pending_split_factor::Float64
    value_settle::Price
    init_margin_settle::Price
    maint_margin_settle::Price
end

@inline _FillPositionState(pos::Position) = _FillPositionState(
    pos.quantity,
    pos.avg_entry_price,
    pos.avg_entry_price_settle,
    pos.avg_settle_price,
    pos.entry_commission_quote_carry,
    pos.variation_margin_pnl_settle_carry,
    pos.pending_split_factor,
    pos.value_settle,
    pos.init_margin_settle,
    pos.maint_margin_settle,
)
