"""
Maintenance margin deficit in base currency (zero if none).
"""
@inline function maint_deficit_base_ccy(acc)::Price
    d = maint_margin_used_base_ccy(acc) - equity_base_ccy(acc)
    d > 0 ? d : 0.0
end

"""
Return `true` if the account is below maintenance requirements.
"""
@inline function is_under_maintenance(acc)::Bool
    if acc.margining_style == MarginingStyle.BaseCurrency
        return excess_liquidity_base_ccy(acc) < 0
    end

    @inbounds for i in eachindex(acc.maint_margin_used)
        if acc.equities[i] - acc.maint_margin_used[i] < 0
            return true
        end
    end

    return false
end

"""
Initial margin deficit in base currency (zero if no deficit).
"""
@inline function init_deficit_base_ccy(acc)::Price
    d = init_margin_used_base_ccy(acc) - equity_base_ccy(acc)
    d > 0 ? d : 0.0
end
