# Positional signatures are the allocation-free hot paths; keyword wrappers are
# kept for user ergonomics and forward directly.

@inline function _update_valuation!(
    acc::Account,
    pos::Position{TTime},
    dt::TTime,
    close_price::Price,
) where {TTime<:Dates.AbstractTime}
    inst = pos.inst
    settlement = inst.spec.settlement
    settle_cash_index = inst.settle_cash_index
    qty = pos.quantity
    basis_price = pos.avg_settle_price

    new_pnl = calc_pnl_quote(inst, qty, close_price, basis_price)

    if settlement == SettlementStyle.VariationMargin
        if pos.value_settle != 0.0
            @inbounds acc.ledger.equities[settle_cash_index] -= pos.value_settle
        end
        pos.value_settle = 0.0
        pos.value_quote = 0.0
        if qty == 0.0
            pos.avg_entry_price = zero(Price)
            pos.avg_entry_price_settle = zero(Price)
            pos.avg_settle_price = zero(Price)
            pos.pnl_quote = 0.0
            pos.pnl_settle = 0.0
            return
        end
        if new_pnl != 0.0
            settled_amount = to_settle(acc, inst, new_pnl)
            @inbounds begin
                acc.ledger.balances[settle_cash_index] += settled_amount
                acc.ledger.equities[settle_cash_index] += settled_amount
            end
            _record_cashflow!(acc, dt, CashflowKind.VariationMargin, settle_cash_index, settled_amount, inst.index)
        end
        pos.pnl_quote = 0.0
        pos.pnl_settle = 0.0
        pos.value_settle = 0.0
        pos.avg_settle_price = close_price
        return
    end

    new_value = calc_value_quote(inst, qty, close_price)
    new_value_settle = to_settle(acc, inst, new_value)
    value_delta_settle = new_value_settle - pos.value_settle
    @inbounds acc.ledger.equities[settle_cash_index] += value_delta_settle
    pos.pnl_quote = new_pnl
    pos.pnl_settle = pnl_settle_principal_exchange(inst, qty, new_value_settle, pos.avg_entry_price_settle)
    pos.value_quote = new_value
    pos.value_settle = new_value_settle
    return
end

"""
Updates position valuation and account equity using the latest mark price.

For principal-exchange instruments, value equals marked notional.
For variation-margin instruments, unrealized P&L is settled into cash at each update.
"""
@inline function update_valuation!(
    acc::Account,
    pos::Position{TTime};
    dt::TTime,
    close_price::Price,
) where {TTime<:Dates.AbstractTime}
    isfinite(close_price) || throw(ArgumentError("update_valuation! requires finite close_price, got $(close_price) at dt=$(dt)."))
    _update_valuation!(acc, pos, dt, close_price)
end

@inline function _update_margin!(
    acc::Account,
    pos::Position,
    close_price::Price,
)
    inst = pos.inst
    margin_cash_index = inst.margin_cash_index

    new_init_margin = margin_init_margin_ccy(acc, inst, pos.quantity, close_price)
    new_maint_margin = margin_maint_margin_ccy(acc, inst, pos.quantity, close_price)
    init_delta = new_init_margin - pos.init_margin_settle
    maint_delta = new_maint_margin - pos.maint_margin_settle
    @inbounds begin
        acc.ledger.init_margin_used[margin_cash_index] += init_delta
        acc.ledger.maint_margin_used[margin_cash_index] += maint_delta
    end
    pos.init_margin_settle = new_init_margin
    pos.maint_margin_settle = new_maint_margin
    return
end

"""
Updates margin usage for a position and corresponding account totals.

The function applies deltas to account margin vectors and stores the new
margin values on the position.
"""
@inline function update_margin!(acc::Account, pos::Position; close_price::Price)
    isfinite(close_price) || throw(ArgumentError("update_margin! requires finite close_price, got $(close_price)."))
    _update_margin!(acc, pos, close_price)
end

@inline function _update_marks!(
    acc::Account,
    pos::Position{TTime},
    dt::TTime,
    close_price::Price,
    bid::Price,
    ask::Price,
    last_price::Price,
    recompute_options::Bool=true,
) where {TTime<:Dates.AbstractTime}
    _update_valuation!(acc, pos, dt, close_price)
    if pos.inst.spec.settlement != SettlementStyle.VariationMargin
        pos.avg_settle_price = pos.avg_entry_price
    end
    pos.mark_price = close_price
    pos.last_bid = bid
    pos.last_ask = ask
    pos.last_price = last_price
    pos.mark_time = dt

    if pos.inst.spec.contract_kind == ContractKind.Option
        if recompute_options && pos.quantity != 0.0
            mark_option_position_dirty!(acc, pos.inst.index)
            recompute_dirty_option_groups!(acc)
        end
        return
    end

    margin_price = margin_reference_price(acc, pos.inst, close_price, last_price)
    _update_margin!(acc, pos, margin_price)
    return
end

@inline function _update_marks_from_quotes!(
    acc::Account,
    pos::Position{TTime},
    dt::TTime,
    bid::Price,
    ask::Price,
    last::Price,
    recompute_option_margins::Bool,
) where {TTime<:Dates.AbstractTime}
    isfinite(bid) || throw(ArgumentError("update_marks! requires finite bid, got $(bid) at dt=$(dt)."))
    isfinite(ask) || throw(ArgumentError("update_marks! requires finite ask, got $(ask) at dt=$(dt)."))
    isfinite(last) || throw(ArgumentError("update_marks! requires finite last, got $(last) at dt=$(dt)."))
    _validate_option_mark_prices(pos.inst, bid, ask, last)
    close_price = _calc_mark_price(pos.inst, pos.quantity, bid, ask)
    _update_marks!(acc, pos, dt, close_price, bid, ask, last, recompute_option_margins)
end

"""
Updates valuation and margin for a position using the latest bid/ask/last.

Valuation uses a liquidation-aware mark (bid/ask, mid when flat; mid for VM).
Margin uses mark prices for variation-margin instruments; otherwise it uses
liquidation marks in fully funded accounts and `last` in margined accounts.
"""
@inline function update_marks!(
    acc::Account,
    pos::Position{TTime},
    dt::TTime,
    bid::Price,
    ask::Price,
    last::Price,
) where {TTime<:Dates.AbstractTime}
    _update_marks_from_quotes!(acc, pos, dt, bid, ask, last, true)
end

@inline function _calc_mark_price(inst::Instrument, qty, bid, ask)
    # Variation margin instruments should mark at a neutral price to avoid spread bleed.
    if inst.spec.settlement == SettlementStyle.VariationMargin
        return (bid + ask) / 2
    end
    if qty > 0
        return bid
    elseif qty < 0
        return ask
    else
        return (bid + ask) / 2
    end
end

@inline function _forced_close_quotes(pos::Position)
    isfinite(pos.last_bid) || throw(ArgumentError("Forced close for $(pos.inst.spec.symbol) requires finite last_bid; call update_marks! before expiry/liquidation."))
    isfinite(pos.last_ask) || throw(ArgumentError("Forced close for $(pos.inst.spec.symbol) requires finite last_ask; call update_marks! before expiry/liquidation."))
    bid = pos.last_bid
    ask = pos.last_ask
    fill_price = pos.quantity > 0.0 ? bid : ask
    fill_price, bid, ask
end

"""
Marks an instrument by bid/ask/last, updating its position valuation, margin, and mark stamp.

Uses mid for variation-margin instruments and side-aware bid/ask for others,
then applies settlement-aware margin reference pricing.
"""
@inline function update_marks!(
    acc::Account{TTime},
    inst::Instrument{TTime},
    dt::TTime,
    bid::Price,
    ask::Price,
    last::Price,
) where {TTime<:Dates.AbstractTime}
    pos = get_position(acc, inst)
    _update_marks_from_quotes!(acc, pos, dt, bid, ask, last, true)
end

@inline function _fill_order_after_validation!(
    acc::Account{TTime,TBroker},
    order::Order{TTime},
    dt::TTime,
    fill_price::Price,
    fill_qty::Quantity,
    is_maker::Bool,
    trade_reason::TradeReason.T,
    underlying_price::Price,
    bid::Price,
    ask::Price,
    last::Price,
)::Union{Trade{TTime},Nothing} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    inst = order.inst
    if inst.spec.contract_kind == ContractKind.Option && isfinite(underlying_price)
        _set_option_underlying_price!(acc, inst, underlying_price)
    end

    pos = get_position(acc, inst)
    fill_qty = fill_qty != 0 ? fill_qty : order.quantity

    mark_for_position = _calc_mark_price(inst, pos.quantity, bid, ask)
    mark_for_valuation = _calc_mark_price(inst, pos.quantity + fill_qty, bid, ask)
    margin_for_valuation = margin_reference_price(acc, inst, mark_for_valuation, last)
    needs_mark_update = isnan(pos.mark_price) || pos.mark_price != mark_for_position ||
                        pos.last_bid != bid || pos.last_ask != ask || pos.last_price != last || pos.mark_time != dt
    needs_mark_update && _update_marks!(acc, pos, dt, mark_for_position, bid, ask, last)

    _accrue_borrow_fee!(acc, pos, dt)
    pos_qty = pos.quantity
    pos_entry_price = pos.avg_entry_price
    commission_quote = broker_commission(acc.broker, inst, dt, fill_qty, fill_price; is_maker=is_maker)

    plan = plan_fill(
        acc,
        pos,
        order,
        dt,
        fill_price,
        mark_for_valuation,
        margin_for_valuation,
        fill_qty,
        commission_quote.fixed,
        commission_quote.pct,
    )

    rejection = check_fill_constraints(acc, pos, plan)
    rejection == OrderRejectReason.None || throw(OrderRejectError(rejection))

    _apply_fill_plan!(
        acc,
        pos,
        order,
        dt,
        fill_price,
        bid,
        ask,
        last,
        mark_for_valuation,
        plan,
        pos_qty,
        pos_entry_price,
        trade_reason,
    )
end

@inline function _fill_option_order_after_validation!(
    acc::Account{TTime,TBroker},
    order::Order{TTime},
    dt::TTime,
    fill_price::Price,
    fill_qty::Quantity,
    is_maker::Bool,
    trade_reason::TradeReason.T,
    underlying_price::Price,
    bid::Price,
    ask::Price,
    last::Price,
)::Union{Trade{TTime},Nothing} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    inst = order.inst
    pos = get_position(acc, inst)
    fill_qty = fill_qty != 0 ? fill_qty : order.quantity

    mark_for_position = _calc_mark_price(inst, pos.quantity, bid, ask)
    mark_for_valuation = _calc_mark_price(inst, pos.quantity + fill_qty, bid, ask)
    margin_for_valuation = margin_reference_price(acc, inst, mark_for_valuation, last)

    local plan::FillPlan
    local pos_qty::Quantity
    local pos_entry_price::Price

    pos_qty = pos.quantity
    pos_entry_price = pos.avg_entry_price
    commission_quote = broker_commission(acc.broker, inst, dt, fill_qty, fill_price; is_maker=is_maker)

    plan = plan_fill(
        acc,
        pos,
        order,
        dt,
        fill_price,
        mark_for_valuation,
        margin_for_valuation,
        fill_qty,
        commission_quote.fixed,
        commission_quote.pct,
        underlying_price,
    )

    group_ids = acc._option_margin_scratch.group_idx
    empty!(group_ids)
    _push_unique_group!(group_ids, _option_group_id(acc, inst.index))

    current_generation = _begin_option_projection!(acc)
    _set_option_projection_override!(acc, current_generation, inst.index, pos.quantity, mark_for_position)
    current_marked_option_init, _ = _project_option_totals_for_groups!(
        acc,
        acc._option_margin_scratch.current_init,
        acc._option_margin_scratch.current_maint,
        group_ids,
        current_generation,
        inst.spec.underlying_symbol,
        inst.quote_cash_index,
        underlying_price,
    )
    current_option_init, _ = _stored_option_margin_totals(acc)
    current_init_base = _account_init_with_option_totals_base(
        acc,
        current_option_init,
        current_marked_option_init,
    )

    projected_generation = _begin_option_projection!(acc)
    projected_mark = plan.new_qty == 0.0 ? Price(NaN) : mark_for_valuation
    _set_option_projection_override!(acc, projected_generation, inst.index, plan.new_qty, projected_mark)
    projected_option_init, _ = _project_option_totals_for_groups!(
        acc,
        acc._option_margin_scratch.projected_init,
        acc._option_margin_scratch.projected_maint,
        group_ids,
        projected_generation,
        inst.spec.underlying_symbol,
        inst.quote_cash_index,
        underlying_price,
    )
    inc_qty = calc_exposure_increase_quantity(pos.quantity, plan.fill_qty)
    rejection = _check_option_fill_constraints(
        acc,
        pos,
        plan,
        inc_qty,
        current_option_init,
        projected_option_init,
        current_init_base,
    )
    rejection == OrderRejectReason.None || throw(OrderRejectError(rejection))

    if isfinite(underlying_price)
        _set_option_underlying_price!(acc, inst, underlying_price)
    end

    _apply_fill_plan!(
        acc,
        pos,
        order,
        dt,
        fill_price,
        bid,
        ask,
        last,
        mark_for_valuation,
        plan,
        pos_qty,
        pos_entry_price,
        trade_reason,
    )
end

function _apply_fill_plan!(
    acc::Account{TTime,TBroker},
    pos::Position{TTime},
    order::Order{TTime},
    dt::TTime,
    fill_price::Price,
    bid::Price,
    ask::Price,
    last::Price,
    mark_price::Price,
    plan::FillPlan,
    pos_qty::Quantity,
    pos_entry_price::Price,
    trade_reason::TradeReason.T;
    recompute_option_margins::Bool=true,
)::Union{Trade{TTime},Nothing} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    inst = order.inst
    settle_cash_index = inst.settle_cash_index
    margin_cash_index = inst.margin_cash_index
    @inbounds begin
        acc.ledger.balances[settle_cash_index] += plan.cash_delta_settle
        acc.ledger.equities[settle_cash_index] += plan.cash_delta_settle + plan.value_delta_settle
        acc.ledger.init_margin_used[margin_cash_index] += plan.init_margin_delta
        acc.ledger.maint_margin_used[margin_cash_index] += plan.maint_margin_delta
    end

    pos.avg_entry_price = plan.new_avg_entry_price_quote
    pos.avg_entry_price_settle = plan.new_avg_entry_price_settle
    pos.avg_settle_price = plan.new_avg_settle_price
    pos.quantity = plan.new_qty
    pos.entry_commission_quote_carry = plan.new_entry_commission_quote_carry
    pos.pnl_quote = plan.new_pnl_quote
    pos.pnl_settle = plan.new_pnl_settle
    pos.value_quote = plan.new_value_quote
    pos.value_settle = plan.new_value_settle
    pos.init_margin_settle = plan.new_init_margin_settle
    pos.maint_margin_settle = plan.new_maint_margin_settle
    pos.mark_price = mark_price
    pos.last_bid = bid
    pos.last_ask = ask
    pos.last_price = last
    pos.mark_time = dt
    if inst.spec.contract_kind == ContractKind.Option
        _set_option_position_active!(acc, inst.index, pos.quantity != 0.0)
        if recompute_option_margins
            mark_option_position_dirty!(acc, inst.index)
            recompute_dirty_option_groups!(acc)
        end
    end
    if pos.quantity < 0.0 &&
        inst.spec.contract_kind == ContractKind.Spot &&
        inst.spec.settlement == SettlementStyle.PrincipalExchange &&
        inst.spec.short_borrow_rate > 0.0
        pos.borrow_fee_dt = dt
    else
        pos.borrow_fee_dt = TTime(0)
    end

    _record_trade!(
        acc,
        pos,
        order,
        dt,
        fill_price,
        plan,
        pos_qty,
        pos_entry_price,
        trade_reason,
    )
end

"""
Fills an order, applying cash/equity/margin deltas and returning the resulting `Trade`.
Returns `nothing` when `acc.track_trades == false`.
Accrues borrow fees for any eligible principal-exchange spot short exposure up to `dt` and
restarts the borrow-fee clock based on the post-fill position.
Throws `OrderRejectError` when the fill is rejected (inactive instrument or risk checks).
Requires bid/ask/last to deterministically value positions and compute margin during fills.
Risk checks only reject exposure-increasing fills (`inc_qty != 0`).
For variation-margin instruments, fills immediately settle execution-to-mark into cash and reset
the settlement basis (`avg_settle_price`) to the current mark.

Commission is broker-driven by default via `acc.broker`.
"""
@inline function fill_order!(
    acc::Account{TTime,TBroker},
    order::Order{TTime};
    dt::TTime,
    fill_price::Price,
    fill_qty::Quantity=0.0,      # fill quantity, if not provided, order quantity is used (complete fill)
    is_maker::Bool=false,
    trade_reason::TradeReason.T=TradeReason.Normal,
    underlying_price::Price=Price(NaN),
    bid::Price,
    ask::Price,
    last::Price,
)::Union{Trade{TTime},Nothing} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    inst = order.inst
    isfinite(fill_price) || throw(ArgumentError("fill_order! requires finite fill_price, got $(fill_price) at dt=$(dt)."))
    isfinite(bid) || throw(ArgumentError("fill_order! requires finite bid, got $(bid) at dt=$(dt)."))
    isfinite(ask) || throw(ArgumentError("fill_order! requires finite ask, got $(ask) at dt=$(dt)."))
    isfinite(last) || throw(ArgumentError("fill_order! requires finite last, got $(last) at dt=$(dt)."))
    _validate_option_price(inst, "fill_price", fill_price)
    _validate_option_mark_prices(inst, bid, ask, last)
    is_active(inst, dt) || throw(OrderRejectError(OrderRejectReason.InstrumentNotAllowed))
    if inst.spec.contract_kind == ContractKind.Option && isfinite(underlying_price)
        _validate_option_price(inst, "underlying_price", underlying_price)
    end

    if inst.spec.contract_kind == ContractKind.Option
        return _fill_option_order_after_validation!(
            acc,
            order,
            dt,
            fill_price,
            fill_qty,
            is_maker,
            trade_reason,
            underlying_price,
            bid,
            ask,
            last,
        )
    end

    _fill_order_after_validation!(
        acc,
        order,
        dt,
        fill_price,
        fill_qty,
        is_maker,
        trade_reason,
        underlying_price,
        bid,
        ask,
        last,
    )
end

"""
Atomically fill a package of option orders after checking final package margin.

This helper is intended for multi-leg listed-option strategies whose final risk
is lower than the temporary single-leg margin path, such as debit spreads,
butterflies, and condors. It marks every leg, computes the final projected option
portfolio margin and cash/equity state, rejects the whole package if that final
state is not fundable, and only then records the fills.
Returns the recorded trades, or an empty vector when `acc.track_trades == false`.
"""
function fill_option_strategy!(
    acc::Account{TTime,TBroker},
    orders::Vector{Order{TTime}};
    dt::TTime,
    fill_prices::Vector{Price},
    bids::Vector{Price}=fill_prices,
    asks::Vector{Price}=fill_prices,
    lasts::Vector{Price}=fill_prices,
    fill_qtys::Union{Nothing,Vector{Quantity}}=nothing,
    is_makers::Union{Nothing,Vector{Bool}}=nothing,
    trade_reason::TradeReason.T=TradeReason.Normal,
    underlying_price::Price=Price(NaN),
)::Vector{Trade{TTime}} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    _fill_option_strategy!(
        acc,
        orders,
        dt,
        fill_prices,
        bids,
        asks,
        lasts,
        fill_qtys,
        is_makers,
        trade_reason,
        underlying_price,
    )
end

@inline function _strategy_fill_qty(
    order::Order,
    fill_qtys::Union{Nothing,Vector{Quantity}},
    i::Int,
)::Quantity
    if fill_qtys === nothing
        return order.quantity
    end
    qty = @inbounds fill_qtys[i]
    qty != 0.0 ? qty : order.quantity
end

function _fill_option_strategy!(
    acc::Account{TTime,TBroker},
    orders::Vector{Order{TTime}},
    dt::TTime,
    fill_prices::Vector{Price},
    bids::Vector{Price},
    asks::Vector{Price},
    lasts::Vector{Price},
    fill_qtys::Union{Nothing,Vector{Quantity}},
    is_makers::Union{Nothing,Vector{Bool}},
    trade_reason::TradeReason.T,
    underlying_price::Price,
)::Vector{Trade{TTime}} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    n = length(orders)
    n > 0 || throw(ArgumentError("fill_option_strategy! requires at least one order."))
    length(fill_prices) == n || throw(ArgumentError("fill_option_strategy! requires one fill_price per order."))
    length(bids) == n || throw(ArgumentError("fill_option_strategy! requires one bid per order."))
    length(asks) == n || throw(ArgumentError("fill_option_strategy! requires one ask per order."))
    length(lasts) == n || throw(ArgumentError("fill_option_strategy! requires one last per order."))
    fill_qtys === nothing || length(fill_qtys) == n || throw(ArgumentError("fill_option_strategy! requires one fill_qty per order."))
    is_makers === nothing || length(is_makers) == n || throw(ArgumentError("fill_option_strategy! requires one is_maker flag per order."))

    first_underlying = orders[1].inst.spec.underlying_symbol
    first_quote = orders[1].inst.spec.quote_symbol
    @inbounds for i in 1:n
        order = orders[i]
        inst = order.inst
        is_option(inst) || throw(ArgumentError("fill_option_strategy! only supports option orders, got $(inst.spec.symbol)."))
        for j in 1:(i - 1)
            orders[j].inst.index == inst.index && throw(ArgumentError("fill_option_strategy! does not support multiple legs for the same instrument $(inst.spec.symbol)."))
        end
        if isfinite(underlying_price) &&
            (inst.spec.underlying_symbol != first_underlying || inst.spec.quote_symbol != first_quote)
            throw(ArgumentError("fill_option_strategy! received one underlying_price but multiple underlying/quote chains."))
        end
        isfinite(fill_prices[i]) || throw(ArgumentError("fill_option_strategy! requires finite fill_price, got $(fill_prices[i]) at dt=$(dt)."))
        isfinite(bids[i]) || throw(ArgumentError("fill_option_strategy! requires finite bid, got $(bids[i]) at dt=$(dt)."))
        isfinite(asks[i]) || throw(ArgumentError("fill_option_strategy! requires finite ask, got $(asks[i]) at dt=$(dt)."))
        isfinite(lasts[i]) || throw(ArgumentError("fill_option_strategy! requires finite last, got $(lasts[i]) at dt=$(dt)."))
        _validate_option_price(inst, "fill_price", fill_prices[i])
        _validate_option_mark_prices(inst, bids[i], asks[i], lasts[i])
        is_active(inst, dt) || throw(OrderRejectError(OrderRejectReason.InstrumentNotAllowed))
    end

    scratch = acc._option_margin_scratch
    positions = resize!(scratch.strategy_positions, n)
    plans = resize!(scratch.strategy_plans, n)
    pos_qtys = resize!(scratch.strategy_pos_qtys, n)
    pos_entry_prices = resize!(scratch.strategy_pos_entry_prices, n)
    projected_mark_prices = resize!(scratch.strategy_projected_mark_prices, n)
    affected_groups = scratch.group_idx
    empty!(affected_groups)
    equity_delta_by_cash = _reset_buffer!(scratch.equity_delta_by_cash, length(acc.ledger.equities), zero(Price))
    projected_generation = _begin_option_projection!(acc)
    commissions = resize!(scratch.strategy_commissions, n)
    broker_option_strategy_commissions!(
        commissions,
        acc.broker,
        orders,
        dt,
        fill_qtys,
        fill_prices,
        is_makers,
    )

    @inbounds for i in 1:n
        order = orders[i]
        inst = order.inst
        pos = get_position(acc, inst)
        positions[i] = pos

        fill_qty = _strategy_fill_qty(order, fill_qtys, i)
        if acc.funding == AccountFunding.FullyFunded && calc_exposure_increase_quantity(pos.quantity, fill_qty) < 0.0
            throw(OrderRejectError(OrderRejectReason.ShortNotAllowed))
        end

        mark_for_valuation = _calc_mark_price(inst, pos.quantity + fill_qty, bids[i], asks[i])
        margin_for_valuation = margin_reference_price(acc, inst, mark_for_valuation, lasts[i])
        commission_quote = commissions[i]

        plan = plan_fill(
            acc,
            pos,
            order,
            dt,
            fill_prices[i],
            mark_for_valuation,
            margin_for_valuation,
            fill_qty,
            commission_quote.fixed,
            commission_quote.pct,
            underlying_price,
        )
        plans[i] = plan
        pos_qtys[i] = pos.quantity
        pos_entry_prices[i] = pos.avg_entry_price
        projected_mark_prices[i] = mark_for_valuation
        _set_option_projection_override!(
            acc,
            projected_generation,
            inst.index,
            plan.new_qty,
            plan.new_qty == 0.0 ? Price(NaN) : mark_for_valuation,
        )
        _push_unique_group!(affected_groups, _option_group_id(acc, inst.index))
        equity_delta_by_cash[inst.settle_cash_index] += plan.cash_delta_settle + plan.value_delta_settle
    end

    current_option_init, _ = _stored_option_margin_totals(acc)
    projected_option_init, _ = _project_option_totals_for_groups!(
        acc,
        scratch.projected_init,
        scratch.projected_maint,
        affected_groups,
        projected_generation,
        first_underlying,
        orders[1].inst.quote_cash_index,
        underlying_price,
    )
    rejection = _check_option_strategy_constraints(
        acc,
        equity_delta_by_cash,
        projected_option_init,
        current_option_init,
    )
    rejection == OrderRejectReason.None || throw(OrderRejectError(rejection))

    if isfinite(underlying_price)
        _set_option_underlying_price!(acc, first_underlying, first_quote, underlying_price)
    end

    trades = Trade{TTime}[]
    acc.track_trades && sizehint!(trades, n)
    @inbounds for i in 1:n
        trade = _apply_fill_plan!(
            acc,
            positions[i],
            orders[i],
            dt,
            fill_prices[i],
            bids[i],
            asks[i],
            lasts[i],
            projected_mark_prices[i],
            plans[i],
            pos_qtys[i],
            pos_entry_prices[i],
            trade_reason;
            recompute_option_margins=false,
        )
        if trade !== nothing
            push!(trades, trade::Trade{TTime})
        end
    end
    @inbounds for group_id in affected_groups
        mark_option_group_dirty!(acc, group_id)
    end
    recompute_dirty_option_groups!(acc)

    trades
end

"""
Roll an open position from one instrument into another at a shared timestamp.

The helper closes the entire `from_inst` exposure first, then opens the same
signed quantity in `to_inst`. Both fills are tagged with `TradeReason.Roll`
and use explicit prices for each leg. Returns recorded trades when
`acc.track_trades == true`, or `(nothing, nothing)` when history tracking is
disabled. Still returns `(nothing, nothing)` when `from_inst` is already flat.

The roll requires matching settlement/margin accounting profile so cashflow and
margin regimes remain continuous. Non-option contracts must share `base_symbol`;
options must share `underlying_symbol`, right, and exercise style.
"""
function roll_position!(
    acc::Account{TTime,TBroker},
    from_inst::Instrument{TTime},
    to_inst::Instrument{TTime},
    dt::TTime;
    close_fill_price::Price,
    open_fill_price::Price,
    close_bid::Price=close_fill_price,
    close_ask::Price=close_fill_price,
    close_last::Price=close_fill_price,
    open_bid::Price=open_fill_price,
    open_ask::Price=open_fill_price,
    open_last::Price=open_fill_price,
)::Tuple{Union{Trade{TTime},Nothing},Union{Trade{TTime},Nothing}} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    from_spec = from_inst.spec
    to_spec = to_inst.spec
    from_inst.index == to_inst.index &&
        throw(ArgumentError("roll_position! requires distinct instruments, got $(from_spec.symbol)."))

    from_is_option = from_spec.contract_kind == ContractKind.Option
    to_is_option = to_spec.contract_kind == ContractKind.Option
    from_is_option == to_is_option ||
        throw(ArgumentError("roll_position! requires matching contract_kind, got $(from_spec.contract_kind) and $(to_spec.contract_kind)."))
    if from_is_option
        from_spec.underlying_symbol == to_spec.underlying_symbol ||
            throw(ArgumentError("roll_position! requires matching underlying_symbol, got $(from_spec.underlying_symbol) and $(to_spec.underlying_symbol)."))
        from_spec.option_right == to_spec.option_right ||
            throw(ArgumentError("roll_position! requires matching option_right, got $(from_spec.option_right) and $(to_spec.option_right)."))
        from_spec.exercise_style == to_spec.exercise_style ||
            throw(ArgumentError("roll_position! requires matching exercise_style, got $(from_spec.exercise_style) and $(to_spec.exercise_style)."))
    else
        from_spec.base_symbol == to_spec.base_symbol ||
            throw(ArgumentError("roll_position! requires matching base_symbol, got $(from_spec.base_symbol) and $(to_spec.base_symbol)."))
    end
    from_spec.quote_symbol == to_spec.quote_symbol ||
        throw(ArgumentError("roll_position! requires matching quote_symbol, got $(from_spec.quote_symbol) and $(to_spec.quote_symbol)."))
    from_spec.multiplier == to_spec.multiplier ||
        throw(ArgumentError("roll_position! requires matching multiplier, got $(from_spec.multiplier) and $(to_spec.multiplier)."))
    from_spec.settle_symbol == to_spec.settle_symbol ||
        throw(ArgumentError("roll_position! requires matching settle_symbol, got $(from_spec.settle_symbol) and $(to_spec.settle_symbol)."))
    from_spec.margin_symbol == to_spec.margin_symbol ||
        throw(ArgumentError("roll_position! requires matching margin_symbol, got $(from_spec.margin_symbol) and $(to_spec.margin_symbol)."))
    from_spec.settlement == to_spec.settlement ||
        throw(ArgumentError("roll_position! requires matching settlement style, got $(from_spec.settlement) and $(to_spec.settlement)."))
    from_spec.margin_requirement == to_spec.margin_requirement ||
        throw(ArgumentError("roll_position! requires matching margin_requirement, got $(from_spec.margin_requirement) and $(to_spec.margin_requirement)."))

    pos = get_position(acc, from_inst)
    qty = pos.quantity
    qty == 0.0 && return nothing, nothing

    close_order = Order(oid!(acc), from_inst, dt, close_fill_price, -qty)
    close_trade = fill_order!(
        acc,
        close_order;
        dt=dt,
        fill_price=close_fill_price,
        bid=close_bid,
        ask=close_ask,
        last=close_last,
        trade_reason=TradeReason.Roll,
    )

    open_order = Order(oid!(acc), to_inst, dt, open_fill_price, qty)
    open_trade = fill_order!(
        acc,
        open_order;
        dt=dt,
        fill_price=open_fill_price,
        bid=open_bid,
        ask=open_ask,
        last=open_last,
        trade_reason=TradeReason.Roll,
    )

    close_trade, open_trade
end

"""
Final-settles an expired futures position at the current mark and releases margin.

For variation-margin futures, expiry applies one last mark-to-market settlement at
`pos.mark_price`, then flattens quantity and clears margin usage without synthetic
bid/ask execution or expiry commissions. Returns `nothing` when
`acc.track_trades == false`.
"""
function settle_expiry!(
    acc::Account{TTime,TBroker},
    inst::Instrument{TTime},
    dt::TTime
)::Union{Trade{TTime},Nothing} where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    inst.spec.contract_kind == ContractKind.Future || throw(ArgumentError("settle_expiry! only supports Future instruments, got $(inst.spec.symbol) with $(inst.spec.contract_kind)."))

    pos = get_position(acc, inst)
    (pos.quantity == 0.0 || !is_expired(inst, dt)) && return nothing

    qty_before = pos.quantity
    avg_entry_before = pos.avg_entry_price
    settle_price = pos.mark_price
    isfinite(settle_price) || throw(ArgumentError("settle_expiry! requires finite mark_price for $(inst.spec.symbol); call update_marks! before expiry settlement."))

    # Realize the final VM settlement amount into cash/equity at expiry.
    _update_valuation!(acc, pos, dt, settle_price)

    margin_idx = inst.margin_cash_index
    @inbounds begin
        acc.ledger.init_margin_used[margin_idx] -= pos.init_margin_settle
        acc.ledger.maint_margin_used[margin_idx] -= pos.maint_margin_settle
    end

    qty_close = -qty_before
    pos.avg_entry_price = 0.0
    pos.avg_entry_price_settle = 0.0
    pos.avg_settle_price = 0.0
    pos.quantity = 0.0
    pos.entry_commission_quote_carry = 0.0
    pos.pnl_quote = 0.0
    pos.pnl_settle = 0.0
    pos.value_quote = 0.0
    pos.value_settle = 0.0
    pos.init_margin_settle = 0.0
    pos.maint_margin_settle = 0.0
    pos.borrow_fee_dt = TTime(0)

    _count_trade!(acc)
    acc.track_trades || return nothing

    order = Order(oid!(acc), inst, dt, settle_price, qty_close)
    notional_quote = abs(settle_price) * abs(qty_close) * inst.spec.multiplier
    notional_base = iszero(notional_quote) ? 0.0 : notional_quote * get_rate_base_ccy(acc, inst.quote_cash_index)
    trade = Trade(
        order,
        tid!(acc),
        dt,
        settle_price,
        qty_close,
        0.0,
        notional_base,
        0.0,        # Final settlement P&L is handled as VM cashflow, not trade execution P&L.
        qty_before,
        0.0,
        0.0,
        0.0,
        0.0,
        qty_before,
        avg_entry_before,
        TradeReason.Expiry,
    )
    pos.last_order = order
    pos.last_trade = trade
    push!(acc.trades, trade)
    trade
end
