"""Base-currency account totals captured at one point in time."""
struct AccountSnapshot
    balance::Price
    equity::Price
    init_margin::Price
    maint_margin::Price
    available_funds::Price
    excess_liquidity::Price
end

function account_snapshot(acc::Account)::AccountSnapshot
    balance = balance_base_ccy(acc)
    equity_value = equity_base_ccy(acc)
    init_margin = init_margin_used_base_ccy(acc)
    maint_margin = maint_margin_used_base_ccy(acc)
    values = (balance, equity_value, init_margin, maint_margin)
    all(isfinite, values) || throw(ArgumentError("Account snapshot contains a non-finite value."))
    AccountSnapshot(
        balance,
        equity_value,
        init_margin,
        maint_margin,
        equity_value - init_margin,
        equity_value - maint_margin,
    )
end

"""Marked gross/net instrument notional and the corresponding account totals."""
struct PortfolioExposure
    snapshot::AccountSnapshot
    gross_notional::Price
    net_notional::Price
end

"""
A complete set of target instrument weights. Weights may be negative and need
not sum to one; cash is the residual. Zero-weight entries retain membership.
"""
struct TargetWeights
    weights::Vector{Pair{Int,Price}}

    TargetWeights(weights::Vector{Pair{Int,Price}}, ::Val{:validated}) = new(weights)
end

@inline _target_index(inst::Instrument) = inst.index
@inline _target_index(index::Integer) = Int(index)

function TargetWeights(weights::Union{AbstractVector,Tuple,AbstractDict})
    validated = Pair{Int,Price}[]
    for entry in weights
        entry isa Pair || throw(ArgumentError("Target weights must be supplied as instrument => weight pairs."))
        index = _target_index(first(entry))
        index > 0 || throw(ArgumentError("Target instrument indices must be positive."))
        weight = Price(last(entry))
        isfinite(weight) || throw(ArgumentError("Target weight must be finite."))
        any(pair -> first(pair) == index, validated) &&
            throw(ArgumentError("Target contains instrument index $(index) more than once."))
        push!(validated, index => (weight == 0.0 ? 0.0 : weight))
    end
    sort!(validated; by=first)
    TargetWeights(validated, Val(:validated))
end

TargetWeights(weights::Pair...) = TargetWeights(weights)
Base.length(target::TargetWeights) = length(target.weights)
Base.isempty(target::TargetWeights) = isempty(target.weights)
Base.iterate(target::TargetWeights, state...) = iterate(target.weights, state...)

function _validate_target_weights(target::TargetWeights)
    previous_index = 0
    @inbounds for pair in target.weights
        index = first(pair)
        weight = last(pair)
        index > previous_index || throw(ArgumentError(
            "Target instrument indices must remain positive, unique, and sorted."
        ))
        isfinite(weight) || throw(ArgumentError("Target weight must be finite."))
        previous_index = index
    end
    nothing
end

@inline function _target_weight(target::TargetWeights, index::Int)
    @inbounds for pair in target.weights
        first(pair) == index && return last(pair)
    end
    nothing
end

"""Controls suppression of small trades and treatment of positions absent from a target."""
struct RebalancePolicy
    minimum_notional_base::Price
    orphan_positions::OrphanPositionPolicy.T

    function RebalancePolicy(
        ;
        minimum_notional_base::Real=0.0,
        orphan_positions::OrphanPositionPolicy.T=OrphanPositionPolicy.Close,
    )
        minimum = Price(minimum_notional_base)
        isfinite(minimum) && minimum >= 0.0 ||
            throw(ArgumentError("minimum_notional_base must be non-negative and finite."))
        new(minimum == 0.0 ? 0.0 : minimum, orphan_positions)
    end
end

"""Explicit transition from one concrete futures/perpetual contract to another."""
struct RollTransition
    from_index::Int
    to_index::Int

    function RollTransition(from_index::Integer, to_index::Integer)
        from = Int(from_index)
        to = Int(to_index)
        from > 0 && to > 0 || throw(ArgumentError("Roll instrument indices must be positive."))
        from != to || throw(ArgumentError("Roll source and destination must be distinct."))
        new(from, to)
    end
end

RollTransition(from::Instrument, to::Instrument) = RollTransition(from.index, to.index)

"""Immutable market and requested-quantity inputs supplied to a fill model."""
struct FillContext{TTime<:Dates.AbstractTime}
    dt::TTime
    inst::Instrument{TTime}
    bid::Price
    ask::Price
    last::Price
    quantity::Quantity
    reason::TradeReason.T
end

"""Complete simulated execution observation returned by a portfolio fill model."""
struct ModelFill
    price::Price
    bid::Price
    ask::Price
    last::Price
    is_maker::Bool

    function ModelFill(
        price::Real,
        bid::Real,
        ask::Real,
        last::Real;
        is_maker::Bool=false,
    )
        price_value = Price(price)
        bid_value = Price(bid)
        ask_value = Price(ask)
        last_value = Price(last)
        all(isfinite, (price_value, bid_value, ask_value, last_value)) ||
            throw(ArgumentError("Model fill prices must be finite."))
        bid_value <= ask_value || throw(ArgumentError("Model fill bid cannot exceed ask."))
        new(price_value, bid_value, ask_value, last_value, is_maker)
    end
end

abstract type AbstractFillModel end
struct TopOfBookFillModel <: AbstractFillModel end

struct SpreadFillModel <: AbstractFillModel
    full_spread_basis_points::Price
    minimum_full_spread_ticks::Price

    function SpreadFillModel(
        ;
        full_spread_basis_points::Real=0.0,
        minimum_full_spread_ticks::Real=0.0,
    )
        bps = Price(full_spread_basis_points)
        ticks = Price(minimum_full_spread_ticks)
        isfinite(bps) && bps >= 0.0 ||
            throw(ArgumentError("full_spread_basis_points must be non-negative and finite."))
        isfinite(ticks) && ticks >= 0.0 ||
            throw(ArgumentError("minimum_full_spread_ticks must be non-negative and finite."))
        new(bps, ticks)
    end
end

"""Construct a deterministic fill from a `FillContext`. Extend for custom models."""
@inline function model_fill(::TopOfBookFillModel, context::FillContext)::ModelFill
    price = context.quantity > 0.0 ? context.ask : context.bid
    ModelFill(price, context.bid, context.ask, context.last)
end

@inline function model_fill(model::SpreadFillModel, context::FillContext)::ModelFill
    full_spread = max(
        abs(context.last) * model.full_spread_basis_points / 10_000.0,
        context.inst.spec.quote_tick * model.minimum_full_spread_ticks,
    )
    half_spread = full_spread / 2.0
    bid = min(context.bid, context.last - half_spread)
    ask = max(context.ask, context.last + half_spread)
    price = context.quantity > 0.0 ? ask : bid
    ModelFill(price, bid, ask, context.last)
end

"""Result of a completed target-weight rebalance."""
struct RebalanceResult{TTime<:Dates.AbstractTime}
    trades::Vector{Trade{TTime}}
    suppressed::Vector{Int}
    pretrade::AccountSnapshot
    posttrade::AccountSnapshot
end

"""Thin target-weight management wrapper around an `Account`; it keeps no hidden target state."""
struct Portfolio{TAccount<:Account}
    account::TAccount
end

function portfolio_exposure(portfolio::Portfolio)::PortfolioExposure
    acc = portfolio.account
    snapshot = account_snapshot(acc)
    gross = 0.0
    net = 0.0
    @inbounds for pos in acc.positions
        pos.quantity == 0.0 && continue
        isfinite(pos.mark_price) || throw(ArgumentError("Portfolio exposure requires a mark for $(pos.inst.spec.symbol)."))
        notional_quote = pos.quantity * pos.mark_price * pos.inst.spec.multiplier
        notional_base = to_base(acc, pos.inst.quote_cash_index, notional_quote)
        gross += abs(notional_base)
        net += notional_base
        isfinite(gross) && isfinite(net) || throw(ArgumentError("Portfolio notional overflowed."))
    end
    PortfolioExposure(snapshot, gross, net)
end

mutable struct _RebalanceLeg{TTime<:Dates.AbstractTime}
    inst::Instrument{TTime}
    quantity::Quantity
    reduction::Bool
    fill::Union{Nothing,ModelFill}
end

@inline function _portfolio_market(pos::Position)
    pos.mark_time != typeof(pos.mark_time)(0) ||
        throw(ArgumentError("Rebalancing requires a timestamped mark for $(pos.inst.spec.symbol)."))
    all(isfinite, (pos.last_bid, pos.last_ask, pos.last_price)) ||
        throw(ArgumentError("Rebalancing requires complete stored quotes for $(pos.inst.spec.symbol)."))
    pos.last_bid <= pos.last_ask ||
        throw(ArgumentError("Rebalancing requires non-crossed quotes for $(pos.inst.spec.symbol)."))
    (bid=pos.last_bid, ask=pos.last_ask, last=pos.last_price)
end

@inline function _build_model_fill(
    model::AbstractFillModel,
    dt::TTime,
    pos::Position{TTime},
    qty::Quantity,
    reason::TradeReason.T,
) where {TTime<:Dates.AbstractTime}
    market = _portfolio_market(pos)
    context = FillContext(dt, pos.inst, market.bid, market.ask, market.last, qty, reason)
    model_fill(model, context)
end

struct _PlannedRoll{TTime<:Dates.AbstractTime}
    from_inst::Instrument{TTime}
    to_inst::Instrument{TTime}
    close_fill::ModelFill
    open_fill::ModelFill
end

@inline function _portfolio_registered_instrument(
    acc::Account,
    index::Int,
)
    1 <= index <= length(acc.positions) ||
        throw(ArgumentError("Target instrument index $(index) is not registered."))
    acc.positions[index].inst
end

function _validate_portfolio_instrument(
    acc::Account{TTime},
    index::Int,
    dt::TTime,
) where {TTime<:Dates.AbstractTime}
    inst = _portfolio_registered_instrument(acc, index)
    pos = acc.positions[index]
    inst.spec.contract_kind != ContractKind.Option || throw(ArgumentError(
        "Target-weight rebalancing does not support option $(inst.spec.symbol); use fill_option_strategy!."
    ))
    is_active(inst, dt) || throw(ArgumentError("Instrument $(inst.spec.symbol) is not active at $(dt)."))
    (pos.mark_time != TTime(0) && dt < pos.mark_time) &&
        throw(ArgumentError("Rebalance datetime $(dt) precedes the last mark for $(inst.spec.symbol)."))
    _portfolio_market(pos)
    get_rate_base_ccy(acc, inst.quote_cash_index)
    get_rate(acc, inst.quote_cash_index, inst.settle_cash_index)
    get_rate(acc, inst.quote_cash_index, inst.margin_cash_index)
    get_rate_base_ccy(acc, inst.settle_cash_index)
    get_rate_base_ccy(acc, inst.margin_cash_index)
    inst
end

function _validate_portfolio_roll_compatibility(from::Instrument, to::Instrument)
    a = from.spec
    b = to.spec
    a.contract_kind in (ContractKind.Future, ContractKind.Perpetual) &&
        b.contract_kind in (ContractKind.Future, ContractKind.Perpetual) ||
        throw(ArgumentError("Portfolio rolls require futures or perpetual instruments."))
    a.contract_kind == b.contract_kind ||
        throw(ArgumentError("Roll instruments must have matching contract_kind."))
    a.base_symbol == b.base_symbol || throw(ArgumentError("Roll instruments must have matching base_symbol."))
    a.quote_symbol == b.quote_symbol || throw(ArgumentError("Roll instruments must have matching quote_symbol."))
    a.settle_symbol == b.settle_symbol || throw(ArgumentError("Roll instruments must have matching settle_symbol."))
    a.margin_symbol == b.margin_symbol || throw(ArgumentError("Roll instruments must have matching margin_symbol."))
    a.settlement == b.settlement || throw(ArgumentError("Roll instruments must have matching settlement style."))
    a.margin_requirement == b.margin_requirement || throw(ArgumentError("Roll instruments must have matching margin requirement."))
    a.multiplier == b.multiplier || throw(ArgumentError("Roll instruments must have matching multiplier."))
    nothing
end

function _ordered_rolls(
    acc::Account,
    target::TargetWeights,
    rolls::AbstractVector{RollTransition},
)
    sources = Set{Int}()
    pending = collect(rolls)
    @inbounds for transition in pending
        transition.from_index in sources &&
            throw(ArgumentError("Roll source index $(transition.from_index) appears more than once."))
        push!(sources, transition.from_index)
        _target_weight(target, transition.to_index) === nothing &&
            throw(ArgumentError("Roll destination index $(transition.to_index) is absent from the target."))
        from = _portfolio_registered_instrument(acc, transition.from_index)
        to = _portfolio_registered_instrument(acc, transition.to_index)
        _validate_portfolio_roll_compatibility(from, to)
    end

    ordered = RollTransition[]
    while !isempty(pending)
        selected = 0
        @inbounds for i in eachindex(pending)
            destination = pending[i].to_index
            destination_is_source = any(t -> t.from_index == destination, pending)
            if !destination_is_source
                selected = i
                break
            end
        end
        selected != 0 || throw(ArgumentError("Roll transitions contain a cycle."))
        push!(ordered, splice!(pending, selected))
    end
    ordered, sources
end

@inline function _estimated_rebalance_cash_delta(
    acc::Account{TTime,TBroker},
    pos::Position{TTime},
    dt::TTime,
    qty::Quantity,
    fill::ModelFill,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    inst = pos.inst
    commission = broker_commission(acc.broker, inst, dt, qty, fill.price; is_maker=fill.is_maker)
    notional_abs = abs(fill.price) * abs(qty) * inst.spec.multiplier
    commission_quote = commission.fixed + commission.pct * notional_abs
    cash_quote = if inst.spec.settlement == SettlementStyle.PrincipalExchange
        cash_delta_quote_principal_exchange(inst, qty, fill.price, commission_quote)
    else
        realized = calc_realized_qty(pos.quantity, qty)
        realized_pnl = calc_pnl_quote(inst, realized, fill.price, pos.avg_settle_price)
        realized_pnl - commission_quote
    end
    to_settle(acc, inst, cash_quote)
end

@inline function _scaled_increase_quantity(inst::Instrument, qty::Quantity, scale::Price)::Quantity
    qty <= 0.0 && return qty
    tick_count = trunc(_snap_tick_count_near_integer(qty * scale / inst.spec.base_tick))
    scaled = tick_count * inst.spec.base_tick
    scaled <= 0.0 && return 0.0
    minimum = max(inst.spec.base_min, 0.0)
    scaled < minimum && return 0.0
    maximum = floor(_snap_tick_count_near_integer(inst.spec.base_max / inst.spec.base_tick)) * inst.spec.base_tick
    Quantity(min(scaled, maximum))
end

function _scale_fully_funded_increases!(
    acc::Account{TTime,TBroker},
    dt::TTime,
    legs::Vector{_RebalanceLeg{TTime}},
    model::AbstractFillModel,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    available = copy(acc.ledger.balances)
    @inbounds for leg in legs
        leg.reduction || continue
        fill = _build_model_fill(model, dt, get_position(acc, leg.inst), leg.quantity, TradeReason.Normal)
        idx = leg.inst.settle_cash_index
        available[idx] += _estimated_rebalance_cash_delta(acc, get_position(acc, leg.inst), dt, leg.quantity, fill)
        isfinite(available[idx]) || throw(ArgumentError("Projected cash balance overflowed."))
    end
    any(balance -> balance < -1.0e-9, available) &&
        throw(ArgumentError("Fully funded reductions leave a negative cash balance."))

    function satisfies(scale::Price)
        remaining = copy(available)
        @inbounds for leg in legs
            leg.reduction && continue
            inst = leg.inst
            inst.spec.settlement == SettlementStyle.PrincipalExchange || continue
            leg.quantity > 0.0 || continue
            qty = _scaled_increase_quantity(inst, leg.quantity, scale)
            qty == 0.0 && continue
            pos = get_position(acc, inst)
            fill = _build_model_fill(model, dt, pos, qty, TradeReason.Normal)
            idx = inst.settle_cash_index
            remaining[idx] += _estimated_rebalance_cash_delta(acc, pos, dt, qty, fill)
            isfinite(remaining[idx]) || return false
        end
        all(balance -> balance >= -1.0e-9, remaining)
    end

    satisfies(1.0) && return legs
    lower = 0.0
    upper = 1.0
    for _ in 1:64
        middle = (lower + upper) / 2.0
        if satisfies(middle)
            lower = middle
        else
            upper = middle
        end
    end
    @inbounds for leg in legs
        if !leg.reduction &&
           leg.inst.spec.settlement == SettlementStyle.PrincipalExchange &&
           leg.quantity > 0.0
            leg.quantity = _scaled_increase_quantity(leg.inst, leg.quantity, lower)
        end
    end
    legs
end

function _plan_rebalance(
    acc::Account{TTime,TBroker},
    dt::TTime,
    target::TargetWeights,
    rolls::AbstractVector{RollTransition},
    policy::RebalancePolicy,
    model::AbstractFillModel,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    _validate_account_timestamp(acc, dt)
    _validate_target_weights(target)
    pretrade = account_snapshot(acc)
    pretrade.equity > 0.0 || throw(ArgumentError("Pretrade account equity must be positive."))

    ordered_rolls, roll_sources = _ordered_rolls(acc, target, rolls)
    n = length(acc.positions)
    current = Vector{Quantity}(undef, n)
    desired = zeros(Quantity, n)
    target_member = falses(n)
    @inbounds for i in 1:n
        current[i] = acc.positions[i].quantity
    end

    @inbounds for pair in target.weights
        index = first(pair)
        weight = last(pair)
        candidate = _portfolio_registered_instrument(acc, index)
        candidate.spec.contract_kind != ContractKind.Option || throw(ArgumentError(
            "Target-weight rebalancing does not support option $(candidate.spec.symbol); use fill_option_strategy!."
        ))
        target_member[index] = true
        if weight == 0.0 && current[index] == 0.0
            continue
        end
        inst = _validate_portfolio_instrument(acc, index, dt)
        target_notional_base = weight * pretrade.equity
        isfinite(target_notional_base) || throw(ArgumentError("Target notional overflowed."))
        quote_to_base = get_rate_base_ccy(acc, inst.quote_cash_index)
        target_notional_quote = target_notional_base / quote_to_base
        desired[index] = calc_base_qty_for_notional(inst, acc.positions[index].last_price, target_notional_quote)
        if acc.funding == AccountFunding.FullyFunded && desired[index] < 0.0
            throw(ArgumentError("Fully funded accounts cannot target short exposure in $(inst.spec.symbol)."))
        end
    end

    @inbounds for i in 1:n
        current[i] == 0.0 && continue
        target_member[i] && continue
        _validate_portfolio_instrument(acc, i, dt)
        if !(i in roll_sources) && policy.orphan_positions == OrphanPositionPolicy.Reject
            throw(ArgumentError("Open position $(acc.positions[i].inst.spec.symbol) is absent from the complete target."))
        end
    end

    planned_rolls = _PlannedRoll{TTime}[]
    @inbounds for transition in ordered_rolls
        source_qty = current[transition.from_index]
        (source_qty == 0.0 || desired[transition.to_index] == 0.0) && continue
        from_pos = acc.positions[transition.from_index]
        to_pos = acc.positions[transition.to_index]
        close_fill = _build_model_fill(model, dt, from_pos, -source_qty, TradeReason.Roll)
        open_fill = _build_model_fill(model, dt, to_pos, source_qty, TradeReason.Roll)
        push!(planned_rolls, _PlannedRoll(from_pos.inst, to_pos.inst, close_fill, open_fill))
        current[transition.from_index] = 0.0
        current[transition.to_index] += source_qty
        isfinite(current[transition.to_index]) || throw(ArgumentError("Post-roll quantity overflowed."))
    end

    legs = _RebalanceLeg{TTime}[]
    suppressed = Int[]
    @inbounds for i in 1:n
        delta = desired[i] - current[i]
        delta == 0.0 && continue
        pos = acc.positions[i]
        inst = pos.inst
        full_exit = desired[i] == 0.0
        notional_quote = abs(delta) * abs(pos.last_price) * inst.spec.multiplier
        notional_base = to_base(acc, inst.quote_cash_index, notional_quote)
        if !full_exit && notional_base < policy.minimum_notional_base
            push!(suppressed, i)
            continue
        end
        if current[i] * desired[i] < 0.0
            push!(legs, _RebalanceLeg(inst, -current[i], true, nothing))
            push!(legs, _RebalanceLeg(inst, desired[i], false, nothing))
        else
            reduction = current[i] != 0.0 &&
                        sign(current[i]) != sign(delta) &&
                        abs(desired[i]) < abs(current[i])
            push!(legs, _RebalanceLeg(inst, delta, reduction, nothing))
        end
    end
    sort!(legs; by=leg -> (!leg.reduction, leg.inst.index))
    acc.funding == AccountFunding.FullyFunded &&
        _scale_fully_funded_increases!(acc, dt, legs, model)
    @inbounds for leg in legs
        leg.quantity == 0.0 && continue
        leg.fill = _build_model_fill(model, dt, get_position(acc, leg.inst), leg.quantity, TradeReason.Normal)
    end
    pretrade, planned_rolls, legs, suppressed
end

"""
    rebalance!(portfolio, dt, target; rolls=[], policy=RebalancePolicy(), fill_model=TopOfBookFillModel())

Move the wrapped account toward complete target weights. Explicit rolls run
first; reversals and all other reductions precede increases. Planning errors do
not mutate the account. Once execution starts, successful earlier fills remain
committed if a later independent fill fails.
"""
function rebalance!(
    portfolio::Portfolio{TAccount},
    dt::TTime,
    target::TargetWeights;
    rolls::AbstractVector{RollTransition}=RollTransition[],
    policy::RebalancePolicy=RebalancePolicy(),
    fill_model::AbstractFillModel=TopOfBookFillModel(),
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker,TAccount<:Account{TTime,TBroker}}
    acc = portfolio.account
    pretrade, planned_rolls, legs, suppressed =
        _plan_rebalance(acc, dt, target, rolls, policy, fill_model)
    trades = Trade{TTime}[]

    @inbounds for roll in planned_rolls
        close_fill = roll.close_fill
        open_fill = roll.open_fill
        close_trade, open_trade = roll_position!(
            acc,
            roll.from_inst,
            roll.to_inst,
            dt;
            close_fill_price=close_fill.price,
            open_fill_price=open_fill.price,
            close_bid=close_fill.bid,
            close_ask=close_fill.ask,
            close_last=close_fill.last,
            open_bid=open_fill.bid,
            open_ask=open_fill.ask,
            open_last=open_fill.last,
        )
        close_trade === nothing || push!(trades, close_trade)
        open_trade === nothing || push!(trades, open_trade)
    end

    @inbounds for leg in legs
        leg.quantity == 0.0 && continue
        fill = leg.fill::ModelFill
        order = create_order!(acc, leg.inst, dt, fill.price, leg.quantity)
        trade = fill_order!(
            acc,
            order;
            dt=dt,
            fill_price=fill.price,
            fill_qty=leg.quantity,
            is_maker=fill.is_maker,
            bid=fill.bid,
            ask=fill.ask,
            last=fill.last,
        )
        trade === nothing || push!(trades, trade)
    end

    RebalanceResult(trades, suppressed, pretrade, account_snapshot(acc))
end
