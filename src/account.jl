struct _FXDependentPosition
    index::Int
    effects::UInt8
end

mutable struct _FXRouteDependents
    const positions::Vector{_FXDependentPosition}
    common_effects::UInt8
end

_FXRouteDependents() = _FXRouteDependents(_FXDependentPosition[], UInt8(3))

mutable struct _AccountEventState
    const short_positions::Vector{Int}
    const borrow_positions::Vector{Int}
    const borrow_amounts::Vector{Price}
    const expiry_positions::Vector{Int}
    const due_expiries::Vector{Int}
    const fx_dependents::Dict{Tuple{Int,Int},_FXRouteDependents}
    const fx_effects::Vector{UInt8}
    const fx_positions::Vector{Int}
    short_proceeds_dirty::Bool
end

_AccountEventState() = _AccountEventState(
    Int[],
    Int[],
    Price[],
    Int[],
    Int[],
    Dict{Tuple{Int,Int},_FXRouteDependents}(),
    UInt8[],
    Int[],
    false,
)

mutable struct OptionMarginScratch{TTime<:Dates.AbstractTime}
    const init_by_pos::Vector{Price}
    const maint_by_pos::Vector{Price}
    const qty_by_pos::Vector{Quantity}
    const mark_by_pos::Vector{Price}
    const override_generation::Vector{Int}
    const override_qty::Vector{Quantity}
    const override_mark::Vector{Price}
    const processed::Vector{Bool}
    const group_idx::Vector{Int}
    const current_init::Vector{Price}
    const current_maint::Vector{Price}
    const projected_init::Vector{Price}
    const projected_maint::Vector{Price}
    const equity_delta_by_cash::Vector{Price}
    const strategy_positions::Vector{Position{TTime}}
    const strategy_plans::Vector{FillPlan}
    const strategy_pos_qtys::Vector{Quantity}
    const strategy_pos_entry_prices::Vector{Price}
    const strategy_projected_mark_prices::Vector{Price}
    const strategy_commissions::Vector{CommissionQuote}
    const projected_active_positions::Vector{Int}
    const override_indices::Vector{Int}
    const projected_group_margins::Vector{NTuple{3,Price}}
    generation::Int
end

const OptionUnderlyingKey = Tuple{Symbol,Symbol}

struct OptionMarginGroupKey{TTime<:Dates.AbstractTime}
    underlying_symbol::Symbol
    expiry::TTime
    multiplier::Float64
    quote_cash_index::Int
    settle_cash_index::Int
    margin_cash_index::Int
end

mutable struct OptionMarginGroup{TTime<:Dates.AbstractTime}
    const key::OptionMarginGroupKey{TTime}
    const positions::Vector{Int}
    const sorted_positions::Vector{Int}
    const active_positions::Vector{Int}
    const sorted_active_positions::Vector{Int}
    dirty::Bool
    underlying_price::Price
    init_total::Price
    maint_total::Price
end

OptionMarginScratch{TTime}() where {TTime<:Dates.AbstractTime} = OptionMarginScratch{TTime}(
    Price[],
    Price[],
    Quantity[],
    Price[],
    Int[],
    Quantity[],
    Price[],
    Bool[],
    Int[],
    Price[],
    Price[],
    Price[],
    Price[],
    Price[],
    Position{TTime}[],
    FillPlan[],
    Quantity[],
    Price[],
    Price[],
    CommissionQuote[],
    Int[],
    Int[],
    NTuple{3,Price}[],
    0,
)

mutable struct Account{TTime<:Dates.AbstractTime,TBroker<:AbstractBroker,TrackTrades}
    const funding::AccountFunding.T
    const margin_aggregation::MarginAggregation.T
    const ledger::CashLedger
    const base_currency::Cash
    const exchange_rates::ExchangeRates
    const broker::TBroker
    const positions::Vector{Position{TTime}}
    const trades::Vector{Trade{TTime}}
    const cashflows::Vector{Cashflow{TTime}}
    const option_underlying_prices::Dict{OptionUnderlyingKey,Price}
    const _fx_update_last_indices::Dict{Tuple{Int,Int},Int}
    const _option_underlying_update_last_indices::Dict{OptionUnderlyingKey,Int}
    const _mark_update_last_indices::Vector{Int}
    const option_position_indices::Vector{Int}
    const option_position_active::Vector{Bool}
    const option_group_id_by_pos::Vector{Int}
    const option_groups::Vector{OptionMarginGroup{TTime}}
    const option_group_lookup::Dict{OptionMarginGroupKey{TTime},Int}
    const option_group_ids_by_underlying::Dict{OptionUnderlyingKey,Vector{Int}}
    const dirty_option_groups::Vector{Int}
    const dirty_option_group_flags::Vector{Bool}
    const option_init_by_cash::Vector{Price}
    const option_maint_by_cash::Vector{Price}
    const _option_margin_scratch::OptionMarginScratch{TTime}
    const _expiry_trades_buffer::Vector{Trade{TTime}}
    const _event_state::_AccountEventState
    const track_trades::Bool
    const track_cashflows::Bool
    poisoned::Bool
    order_sequence::Int
    trade_sequence::Int
    trade_count::Int
    cashflow_sequence::Int
    last_event_dt::TTime
    last_interest_dt::TTime
    const date_format::Dates.DateFormat
    const datetime_format::Dates.DateFormat

    function Account(
        ;
        base_currency::CashSpec,
        time_type::Type{TTime}=DateTime,
        funding::AccountFunding.T=AccountFunding.FullyFunded,
        margin_aggregation::MarginAggregation.T=MarginAggregation.BaseCurrency,
        broker::TBroker,
        track_trades::Bool=true,
        track_cashflows::Bool=true,
        date_format=dateformat"yyyy-mm-dd",
        datetime_format=dateformat"yyyy-mm-dd HH:MM:SS",
        order_sequence=0,
        trade_sequence=0,
        exchange_rates::ExchangeRates=ExchangeRates(),
    ) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
        ledger = CashLedger()
        base_cash = _register_cash_asset!(ledger, base_currency)
        _ensure_rates_size!(exchange_rates, base_cash.index)

        acc = new{TTime,TBroker,track_trades}(
            funding,
            margin_aggregation,
            ledger,
            base_cash,
            exchange_rates,
            broker,
            Vector{Position{TTime}}(), # positions
            Vector{Trade{TTime}}(), # trades
            Vector{Cashflow{TTime}}(), # cashflows
            Dict{OptionUnderlyingKey,Price}(), # option underlying marks by (underlying, quote)
            Dict{Tuple{Int,Int},Int}(), # latest FX observation by unordered cash route
            Dict{OptionUnderlyingKey,Int}(), # latest option-underlying observation by chain
            Int[], # latest mark observation by position index
            Int[], # option position indices
            Bool[], # option active flags by position
            Int[], # option group id by position
            OptionMarginGroup{TTime}[], # option margin groups
            Dict{OptionMarginGroupKey{TTime},Int}(), # option margin group lookup
            Dict{OptionUnderlyingKey,Vector{Int}}(), # option group ids by underlying/quote
            Int[], # dirty option groups
            Bool[], # dirty option group flags
            fill(zero(Price), length(ledger.cash)), # cached option initial margin by cash
            fill(zero(Price), length(ledger.cash)), # cached option maintenance margin by cash
            OptionMarginScratch{TTime}(),
            Vector{Trade{TTime}}(), # reusable expiry buffer
            _AccountEventState(),
            track_trades,
            track_cashflows,
            false, # poisoned
            order_sequence,
            trade_sequence,
            0, # trade_count
            0, # cashflow_sequence
            TTime(0), # last_event_dt
            TTime(0), # last_interest_dt
            date_format,
            datetime_format,
        )
        acc
    end
end

# Expose the constructor's recording choice to inference without changing the
# public track_trades field or specializing on other account configuration.
@inline _tracks_trades(::Account{TTime,TBroker,TrackTrades}) where {TTime,TBroker,TrackTrades} = TrackTrades

@inline function _poison!(acc::Account)
    acc.poisoned = true
    nothing
end

@inline has_cash_asset(acc::Account, symbol::Symbol)::Bool = has_cash_asset(acc.ledger, symbol)
@inline cash_index(acc::Account, symbol::Symbol)::Int = cash_index(acc.ledger, symbol)
@inline cash_asset(acc::Account, symbol::Symbol)::Cash = cash_asset(acc.ledger, symbol)
@inline function cash_asset(acc::Account, idx::Int)::Cash
    _ensure_account_cash_index(acc, idx)
    @inbounds acc.ledger.cash[idx]
end

"""
Registers a new cash asset in the account and synchronizes the FX matrix size.
"""
function register_cash_asset!(acc::Account, spec::CashSpec)::Cash
    cash = _register_cash_asset!(acc.ledger, spec)
    _ensure_rates_size!(acc.exchange_rates, cash.index)
    push!(acc.option_init_by_cash, zero(Price))
    push!(acc.option_maint_by_cash, zero(Price))
    cash
end

"""
Format a timestamp using the account's configured date format.
"""
@inline format_datetime(acc::Account, x::Dates.AbstractDateTime) = Dates.format(x, acc.datetime_format)
@inline format_datetime(acc::Account, x::Dates.Date) = Dates.format(x, acc.date_format)

"""
Generates the next order ID sequence value for the account.

This is a low-level sequence helper and does not validate or advance account
time. Prefer `create_order!` for strategy orders.
"""
@inline oid!(acc::Account) = acc.order_sequence += 1

"""
Generates the next trade ID sequence value for the account.
"""
@inline tid!(acc::Account) = acc.trade_sequence += 1

"""
Generates the next cashflow ID sequence value for the account.
"""
@inline cfid!(acc::Account) = acc.cashflow_sequence += 1

"""
Increments the number of executed/synthetic trades applied to the account.
Unlike `trade_sequence`, this counter advances even when trade history is not stored.
"""
@inline function _count_trade!(acc::Account)
    acc.trade_count += 1
end

@inline function _validate_account_timestamp(acc::Account{TTime}, dt::TTime) where {TTime<:Dates.AbstractTime}
    acc.poisoned && throw(AccountPoisonedError())
    last_dt = acc.last_event_dt
    (last_dt != TTime(0) && dt < last_dt) &&
        throw(ArgumentError("Datetime $(dt) precedes account time $(last_dt)."))
    nothing
end

@inline function _advance_account_timestamp!(acc::Account{TTime}, dt::TTime) where {TTime<:Dates.AbstractTime}
    _validate_account_timestamp(acc, dt)
    acc.last_event_dt = dt
    nothing
end

"""
    create_order!(acc, inst, dt, price, quantity; take_profit=NaN, stop_loss=NaN)

Create a validated account-owned order, assign its sequence ID, and advance the
account clock to `dt`. Validation failures leave both the order sequence and the
account clock unchanged.

Direct `Order(...)` construction remains available for low-level compatibility,
but it cannot update account state.
"""
function create_order!(
    acc::Account{TTime},
    inst::Instrument{TTime},
    dt::TTime,
    price::Real,
    quantity::Real;
    take_profit::Real=Price(NaN),
    stop_loss::Real=Price(NaN),
)::Order{TTime} where {TTime<:Dates.AbstractTime}
    get_position(acc, inst)

    price_p = Price(price)
    quantity_p = Quantity(quantity)
    take_profit_p = Price(take_profit)
    stop_loss_p = Price(stop_loss)
    isfinite(price_p) || throw(ArgumentError("Order price must be finite, got $(price)."))
    isfinite(quantity_p) && quantity_p != 0.0 ||
        throw(ArgumentError("Order quantity must be finite and non-zero, got $(quantity)."))
    _validate_option_price(inst, "order price", price_p)
    (isnan(take_profit_p) || isfinite(take_profit_p)) ||
        throw(ArgumentError("Order take_profit must be finite or NaN, got $(take_profit)."))
    (isnan(stop_loss_p) || isfinite(stop_loss_p)) ||
        throw(ArgumentError("Order stop_loss must be finite or NaN, got $(stop_loss)."))
    _validate_account_timestamp(acc, dt)

    order = Order(
        oid!(acc),
        inst,
        dt,
        price_p,
        quantity_p;
        take_profit=take_profit_p,
        stop_loss=stop_loss_p,
    )
    _advance_account_timestamp!(acc, dt)
    order
end

@inline function _record_cashflow!(
    acc::Account{TTime},
    dt::TTime,
    kind::CashflowKind.T,
    cash_index::Int,
    amount::Price,
    inst_index::Int,
) where {TTime<:Dates.AbstractTime}
    acc.track_cashflows || return nothing
    push!(acc.cashflows, Cashflow{TTime}(cfid!(acc), dt, kind, cash_index, amount, inst_index))
    nothing
end

@inline function _record_trade!(
    acc::Account{TTime},
    pos::Position{TTime},
    order::Order{TTime},
    dt::TTime,
    fill_price::Price,
    plan,
    pos_qty::Quantity,
    pos_entry_price::Price,
    trade_reason::TradeReason.T,
) where {TTime<:Dates.AbstractTime}
    _count_trade!(acc)
    _tracks_trades(acc) || return nothing

    trade = Trade(
        order,
        tid!(acc),
        dt,
        fill_price,
        plan.fill_qty,
        plan.remaining_qty,
        plan.notional_value_base,
        plan.fill_pnl_settle,
        plan.realized_qty,
        plan.commission_quote,
        plan.realized_commission_quote,
        plan.commission_settle,
        plan.cash_delta_settle,
        pos_qty,
        pos_entry_price,
        plan.preceding_split_factor,
        trade_reason,
    )
    pos.last_order = order
    pos.last_trade = trade
    push!(acc.trades, trade)
    trade
end

"""
Deposits cash into the account balance.

Cash is a liquid coin or currency that is used to trade instruments with, e.g. USD, CHF, BTC, ETH.
The cash asset must already be registered in the account.

The funds are added to the balance and equity of the corresponding cash asset.
Use `withdraw!` to reduce the balance again.
Returns the corresponding `Cash` handle.
"""
function deposit!(
    acc::Account{TTime},
    symbol::Symbol,
    amount::Real,
) where {TTime<:Dates.AbstractTime}
    isfinite(amount) && amount >= zero(amount) ||
        throw(ArgumentError("Deposit amount must be non-negative and finite."))
    cash = cash_asset(acc.ledger, symbol)
    deposit!(acc, cash, amount)
end

function deposit!(
    acc::Account{TTime},
    cash::Cash,
    amount::Real,
) where {TTime<:Dates.AbstractTime}
    isfinite(amount) && amount >= zero(amount) ||
        throw(ArgumentError("Deposit amount must be non-negative and finite."))

    idx = _ensure_account_cash(acc, cash)
    _adjust_cash_idx!(acc.ledger, idx, Price(amount))
    @inbounds acc.ledger.cash[idx]
end

"""
Withdraws cash from the account balance.

The cash asset must already be registered in the account.
The funds are subtracted from the balance and equity of the corresponding cash asset.
Use `deposit!` to fund an account.
"""
@inline function _withdraw_idx!(
    acc::Account{TTime},
    idx::Int,
    symbol::Symbol,
    amount::Price,
) where {TTime<:Dates.AbstractTime}
    if acc.funding == AccountFunding.FullyFunded
        @inbounds post_balance = acc.ledger.balances[idx] - amount
        post_balance < 0 && throw(ArgumentError("Withdrawal would overdraw cash balance for $(symbol)."))
        if acc.margin_aggregation == MarginAggregation.PerCurrency
            @inbounds post_available = acc.ledger.equities[idx] - acc.ledger.init_margin_used[idx] - amount
            post_available < 0 && throw(ArgumentError("Withdrawal exceeds available funds for $(symbol)."))
            _adjust_cash_idx!(acc.ledger, idx, -amount)
            return nothing
        else
            amount_base = amount * _get_rate_base_ccy_idx(acc, idx)
            post_available_base = available_funds_base_ccy(acc) - amount_base
            post_available_base < 0 && throw(ArgumentError("Withdrawal exceeds available funds in base currency."))
            _adjust_cash_idx!(acc.ledger, idx, -amount)
            return nothing
        end
    end

    if acc.margin_aggregation == MarginAggregation.PerCurrency
        @inbounds post_available = acc.ledger.equities[idx] - acc.ledger.init_margin_used[idx] - amount
        post_available < 0 && throw(ArgumentError("Withdrawal exceeds available funds for $(symbol)."))
        _adjust_cash_idx!(acc.ledger, idx, -amount)
        return nothing
    else
        amount_base = amount * _get_rate_base_ccy_idx(acc, idx)
        post_available_base = available_funds_base_ccy(acc) - amount_base
        post_available_base < 0 && throw(ArgumentError("Withdrawal exceeds available funds in base currency."))
        _adjust_cash_idx!(acc.ledger, idx, -amount)
        return nothing
    end
end

function withdraw!(
    acc::Account{TTime},
    symbol::Symbol,
    amount::Real,
) where {TTime<:Dates.AbstractTime}
    isfinite(amount) && amount >= zero(amount) ||
        throw(ArgumentError("Withdraw amount must be non-negative and finite."))
    amount_p = Price(amount)
    cash = cash_asset(acc.ledger, symbol)
    _withdraw_idx!(acc, cash.index, cash.symbol, amount_p)
end

@inline function withdraw!(
    acc::Account{TTime},
    cash::Cash,
    amount::Real,
) where {TTime<:Dates.AbstractTime}
    isfinite(amount) && amount >= zero(amount) ||
        throw(ArgumentError("Withdraw amount must be non-negative and finite."))
    amount_p = Price(amount)
    idx = _ensure_account_cash(acc, cash)
    _withdraw_idx!(acc, idx, cash.symbol, amount_p)
end

"""
Registers a new instrument in the account and returns it.

An instrument can only be registered once.
Before trading any instrument, it must be registered in the account.
"""
function register_instrument!(
    acc::Account{TTime},
    spec::InstrumentSpec{TTime}
) where {TTime<:Dates.AbstractTime}
    # ensure instrument symbol is not already registered
    if any(x -> x.inst.spec.symbol == spec.symbol, acc.positions)
        throw(ArgumentError("Instrument $(spec.symbol) already registered"))
    end

    # sanity check instrument parameters
    validate_instrument_spec(spec)

    # ensure cash assets are registered in account
    if !has_cash_asset(acc.ledger, spec.quote_symbol)
        throw(ArgumentError("Quote cash asset '$(spec.quote_symbol)' for instrument '$(spec.symbol)' not registered in account"))
    end
    if !has_cash_asset(acc.ledger, spec.settle_symbol)
        throw(ArgumentError("Settlement cash asset '$(spec.settle_symbol)' for instrument '$(spec.symbol)' not registered in account"))
    end
    if !has_cash_asset(acc.ledger, spec.margin_symbol)
        throw(ArgumentError("Margin cash asset '$(spec.margin_symbol)' for instrument '$(spec.symbol)' not registered in account"))
    end

    quote_cash_index = cash_index(acc.ledger, spec.quote_symbol)
    settle_cash_index = cash_index(acc.ledger, spec.settle_symbol)
    margin_cash_index = cash_index(acc.ledger, spec.margin_symbol)
    index = length(acc.positions) + 1
    inst = Instrument(index, quote_cash_index, settle_cash_index, margin_cash_index, spec)

    # create empty position for the instrument
    push!(acc.positions, Position{TTime}(inst.index, inst))
    push!(acc._mark_update_last_indices, 0)
    push!(acc.option_group_id_by_pos, 0)
    push!(acc.option_position_active, false)
    if spec.contract_kind == ContractKind.Option
        _register_option_position!(acc, inst)
    end
    _register_position_events!(acc, inst)

    inst
end

"""
Returns the position object of the given instrument in the account.
"""
@inline function get_position(acc::Account{TTime}, inst::Instrument{TTime}) where {TTime<:Dates.AbstractTime}
    index = inst.index
    1 <= index <= length(acc.positions) ||
        throw(ArgumentError("Instrument $(inst.spec.symbol) is not registered in this account."))
    @inbounds pos = acc.positions[index]
    pos.inst === inst ||
        throw(ArgumentError("Instrument $(inst.spec.symbol) does not belong to this account."))
    pos
end

"""
Determines if the account has non-zero exposure to the given instrument.
"""
@inline function is_exposed_to(acc::Account{TTime}, inst::Instrument{TTime}) where {TTime<:Dates.AbstractTime}
    has_exposure(get_position(acc, inst))
end

"""
Determines if the account has non-zero exposure to the given instrument
in the given direction (`Buy`, `Sell`).
"""
@inline function is_exposed_to(acc::Account{TTime}, inst::Instrument{TTime}, dir::TradeDir.T) where {TTime<:Dates.AbstractTime}
    sign(trade_dir(get_position(acc, inst))) == sign(dir)
end

"""
Returns the cash balance of the provided cash asset in the account.

The returned value does not include the P&L value of open positions.
"""
@inline function cash_balance(acc::Account, cash::Cash)
    idx = _ensure_account_cash(acc, cash)
    @inbounds acc.ledger.balances[idx]
end

"""
Returns the equity value of the provided cash asset in the account.

Equity is calculated as your cash balance +/- the floating profit/loss
of your open positions in the same currency, not including closing commission.
"""
@inline function equity(acc::Account, cash::Cash)
    idx = _ensure_account_cash(acc, cash)
    @inbounds acc.ledger.equities[idx]
end

"""
Initial margin currently used in the given currency.
"""
@inline function init_margin_used(acc::Account, cash::Cash)::Price
    idx = _ensure_account_cash(acc, cash)
    @inbounds acc.ledger.init_margin_used[idx]
end

"""
Maintenance margin currently used in the given currency.
"""
@inline function maint_margin_used(acc::Account, cash::Cash)::Price
    idx = _ensure_account_cash(acc, cash)
    @inbounds acc.ledger.maint_margin_used[idx]
end

"""
Available funds in a currency (equity minus initial margin used).
"""
@inline available_funds(acc::Account, cash::Cash) = equity(acc, cash) - init_margin_used(acc, cash)

"""
Excess liquidity in a currency (equity minus maintenance margin used).
"""
@inline excess_liquidity(acc::Account, cash::Cash) = equity(acc, cash) - maint_margin_used(acc, cash)

# ---------------------------------------------------------
# Base currency helpers

"""
FX rate from the given cash index into the account base currency.
"""
@inline function _get_rate_base_ccy_idx(acc::Account, i::Int)::Float64
    base_cash = acc.base_currency
    i == base_cash.index && return 1.0
    get_rate(acc.exchange_rates, i, base_cash.index)
end

@inline function _get_rate_idx(
    acc::Account,
    from_idx::Int,
    to_idx::Int,
)
    get_rate(acc.exchange_rates, from_idx, to_idx)
end

"""
FX rate from the given cash asset into the account base currency.
"""
@inline function get_rate_base_ccy(acc::Account, cash::Cash)::Float64
    _get_rate_base_ccy_idx(acc, _ensure_account_cash(acc, cash))
end

"""
FX rate from a cash index into the account base currency.
"""
@inline function get_rate_base_ccy(acc::Account, from_idx::Int)::Float64
    _get_rate_base_ccy_idx(acc, from_idx)
end

"""
FX rate from a cash symbol into the account base currency.
"""
@inline function get_rate_base_ccy(acc::Account, from_symbol::Symbol)::Float64
    _get_rate_base_ccy_idx(acc, cash_index(acc.ledger, from_symbol))
end

@inline function _ensure_account_cash_index(acc::Account, idx::Int)::Int
    n = length(acc.ledger.cash)
    1 <= idx <= n || throw(ArgumentError("Cash index $(idx) not registered in account."))
    idx
end

@inline function _ensure_account_cash(acc::Account, cash::Cash)::Int
    idx = _ensure_account_cash_index(acc, cash.index)
    @inbounds acc.ledger.cash[idx] === cash ||
        throw(ArgumentError("Cash asset $(cash.symbol) does not belong to this account."))
    idx
end

@inline function update_rate!(
    acc::Account,
    from_idx::Int,
    to_idx::Int,
    rate::Real,
)
    _ensure_account_cash_index(acc, from_idx)
    _ensure_account_cash_index(acc, to_idx)
    any(has_exposure, acc.positions) && throw(ArgumentError(
        "Cannot update Account exchange rates directly while exposure is open; use process_step!(...; fx_updates=...) so cached valuations and margins are refreshed."
    ))
    update_rate!(acc.exchange_rates, from_idx, to_idx, rate)
end

@inline function update_rate!(
    acc::Account,
    from::Cash,
    to::Cash,
    rate::Real,
)
    from_idx = _ensure_account_cash(acc, from)
    to_idx = _ensure_account_cash(acc, to)
    update_rate!(acc, from_idx, to_idx, rate)
end

@inline function update_rate!(
    acc::Account,
    from_symbol::Symbol,
    to_symbol::Symbol,
    rate::Real,
)
    from = cash_asset(acc.ledger, from_symbol)
    to = cash_asset(acc.ledger, to_symbol)
    update_rate!(acc, from.index, to.index, rate)
end

@inline function get_rate(
    acc::Account,
    from_idx::Int,
    to_idx::Int,
)
    _ensure_account_cash_index(acc, from_idx)
    _ensure_account_cash_index(acc, to_idx)
    get_rate(acc.exchange_rates, from_idx, to_idx)
end

@inline function get_rate(
    acc::Account,
    from::Cash,
    to::Cash,
)
    get_rate(acc, _ensure_account_cash(acc, from), _ensure_account_cash(acc, to))
end

@inline function get_rate(
    acc::Account,
    from_symbol::Symbol,
    to_symbol::Symbol,
)
    from = cash_asset(acc.ledger, from_symbol)
    to = cash_asset(acc.ledger, to_symbol)
    get_rate(acc.exchange_rates, from, to)
end

# ---------------------------------------------------------
# Currency/unit helpers (see currency/unit semantics note in `contract_math.jl`)

"""
Retrieve the `Cash` object for the instrument quote currency without allocations.
"""
@inline function quote_cash(acc::Account, inst::Instrument)
    get_position(acc, inst)
    @inbounds acc.ledger.cash[inst.quote_cash_index]
end

"""
Retrieve the `Cash` object for the instrument settlement currency without allocations.
"""
@inline function settle_cash(acc::Account, inst::Instrument)
    get_position(acc, inst)
    @inbounds acc.ledger.cash[inst.settle_cash_index]
end

"""
Retrieve the `Cash` object for the instrument margin currency without allocations.
"""
@inline function margin_cash(acc::Account, inst::Instrument)
    get_position(acc, inst)
    @inbounds acc.ledger.cash[inst.margin_cash_index]
end

"""
Total account equity converted into base currency using stored FX rates.
"""
function equity_base_ccy(acc::Account)::Price
    total = zero(Price)
    @inbounds for i in eachindex(acc.ledger.equities)
        val = acc.ledger.equities[i]
        iszero(val) && continue  # avoid 0 * NaN when rate is missing
        total += val * _get_rate_base_ccy_idx(acc, i)
    end
    total
end

"""
Total account cash balance converted into base currency using stored FX rates.
"""
function balance_base_ccy(acc::Account)::Price
    total = zero(Price)
    @inbounds for i in eachindex(acc.ledger.balances)
        val = acc.ledger.balances[i]
        iszero(val) && continue
        total += val * _get_rate_base_ccy_idx(acc, i)
    end
    total
end

"""
Initial margin used, converted into base currency.
"""
function init_margin_used_base_ccy(acc::Account)::Price
    total = zero(Price)
    @inbounds for i in eachindex(acc.ledger.init_margin_used)
        val = acc.ledger.init_margin_used[i]
        iszero(val) && continue
        total += val * _get_rate_base_ccy_idx(acc, i)
    end
    total
end

"""
Maintenance margin used, converted into base currency.
"""
function maint_margin_used_base_ccy(acc::Account)::Price
    total = zero(Price)
    @inbounds for i in eachindex(acc.ledger.maint_margin_used)
        val = acc.ledger.maint_margin_used[i]
        iszero(val) && continue
        total += val * _get_rate_base_ccy_idx(acc, i)
    end
    total
end

"""
Available funds in base currency (equity minus initial margin used).
"""
@inline available_funds_base_ccy(acc::Account)::Price = equity_base_ccy(acc) - init_margin_used_base_ccy(acc)

"""
Excess liquidity in base currency (equity minus maintenance margin used).
"""
@inline excess_liquidity_base_ccy(acc::Account)::Price = equity_base_ccy(acc) - maint_margin_used_base_ccy(acc)

# ---------------------------------------------------------
# FX conversion helpers

"""
Convert a quote-currency amount into the instrument settlement currency.
Naming follows the currency/unit semantics note in `contract_math.jl`.
"""
@inline function to_settle(acc::Account, inst::Instrument, amount_quote::Price)::Price
    iszero(amount_quote) && return 0.0
    isfinite(amount_quote) || throw(ArgumentError("Quote amount must be finite, got $(amount_quote)."))
    result = amount_quote * _get_rate_idx(acc, inst.quote_cash_index, inst.settle_cash_index)
    isfinite(result) || throw(ArgumentError("Quote-to-settlement conversion overflowed."))
    result
end

"""
Convert a settlement-currency amount back into the instrument quote currency.
Inverse of `to_settle`; useful for round-trip tests and diagnostics.
"""
@inline function to_quote(acc::Account, inst::Instrument, amount_settle::Price)::Price
    iszero(amount_settle) && return 0.0
    isfinite(amount_settle) || throw(ArgumentError("Settlement amount must be finite, got $(amount_settle)."))
    result = amount_settle * _get_rate_idx(acc, inst.settle_cash_index, inst.quote_cash_index)
    isfinite(result) || throw(ArgumentError("Settlement-to-quote conversion overflowed."))
    result
end

"""
Convert a quote-currency amount into the instrument margin currency.
"""
@inline function to_margin(acc::Account, inst::Instrument, amount_quote::Price)::Price
    iszero(amount_quote) && return 0.0
    isfinite(amount_quote) || throw(ArgumentError("Quote amount must be finite, got $(amount_quote)."))
    result = amount_quote * _get_rate_idx(acc, inst.quote_cash_index, inst.margin_cash_index)
    isfinite(result) || throw(ArgumentError("Quote-to-margin conversion overflowed."))
    result
end

"""
Convert a margin-currency amount back into the instrument quote currency.
Inverse of `to_margin`; useful for diagnostics.
"""
@inline function to_quote_from_margin(acc::Account, inst::Instrument, amount_margin::Price)::Price
    iszero(amount_margin) && return 0.0
    isfinite(amount_margin) || throw(ArgumentError("Margin amount must be finite, got $(amount_margin)."))
    result = amount_margin * _get_rate_idx(acc, inst.margin_cash_index, inst.quote_cash_index)
    isfinite(result) || throw(ArgumentError("Margin-to-quote conversion overflowed."))
    result
end

"""
Convert a settlement-currency amount into the account base currency.
"""
@inline function to_base(acc::Account, settle_idx::Int, amount_settle::Price)::Price
    iszero(amount_settle) && return 0.0
    isfinite(amount_settle) || throw(ArgumentError("Settlement amount must be finite, got $(amount_settle)."))
    result = amount_settle * _get_rate_base_ccy_idx(acc, settle_idx)
    isfinite(result) || throw(ArgumentError("Settlement-to-base conversion overflowed."))
    result
end

@inline function to_base(acc::Account, cash::Cash, amount_settle::Price)::Price
    to_base(acc, _ensure_account_cash(acc, cash), amount_settle)
end
