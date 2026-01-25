@inline function maint_deficit_base_ccy(acc)::Price
    d = maint_margin_used_base_ccy(acc) - equity_base_ccy(acc)
    d > 0 ? d : 0.0
end

@inline is_under_maintenance(acc)::Bool = excess_liquidity_base_ccy(acc) < 0

@inline function init_deficit_base_ccy(acc)::Price
    d = init_margin_used_base_ccy(acc) - equity_base_ccy(acc)
    d > 0 ? d : 0.0
end
