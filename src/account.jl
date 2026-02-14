mutable struct Account{TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    const mode::AccountMode.T
    const margining_style::MarginingStyle.T
    const ledger::CashLedger
    const base_currency::Cash
    const exchange_rates::ExchangeRates
    const broker::TBroker
    const positions::Vector{Position{TTime}}
    const trades::Vector{Trade{TTime}}
    const cashflows::Vector{Cashflow{TTime}}
    order_sequence::Int
    trade_sequence::Int
    cashflow_sequence::Int
    last_event_dt::TTime
    last_interest_dt::TTime
    const date_format::Dates.DateFormat
    const datetime_format::Dates.DateFormat

    function Account(
        ;
        base_currency::CashSpec,
        time_type::Type{TTime}=DateTime,
        mode::AccountMode.T=AccountMode.Cash,
        margining_style::MarginingStyle.T=MarginingStyle.BaseCurrency,
        broker::TBroker,
        date_format=dateformat"yyyy-mm-dd",
        datetime_format=dateformat"yyyy-mm-dd HH:MM:SS",
        order_sequence=0,
        trade_sequence=0,
        exchange_rates::ExchangeRates=ExchangeRates(),
    ) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
        ledger = CashLedger()
        base_cash = _register_cash_asset!(ledger, base_currency)
        _ensure_rates_size!(exchange_rates, base_cash.index)

        acc = new{TTime,TBroker}(
            mode,
            margining_style,
            ledger,
            base_cash,
            exchange_rates,
            broker,
            Vector{Position{TTime}}(), # positions
            Vector{Trade{TTime}}(), # trades
            Vector{Cashflow{TTime}}(), # cashflows
            order_sequence,
            trade_sequence,
            0, # cashflow_sequence
            TTime(0), # last_event_dt
            TTime(0), # last_interest_dt
            date_format,
            datetime_format,
        )
        acc
    end
end

@inline has_cash_asset(acc::Account, symbol::Symbol)::Bool = has_cash_asset(acc.ledger, symbol)
@inline cash_index(acc::Account, symbol::Symbol)::Int = cash_index(acc.ledger, symbol)
@inline cash_asset(acc::Account, symbol::Symbol)::Cash = cash_asset(acc.ledger, symbol)
@inline cash_asset(acc::Account, idx::Int)::Cash = @inbounds acc.ledger.cash[idx]

"""
Registers a new cash asset in the account and synchronizes the FX matrix size.
"""
function register_cash_asset!(acc::Account, spec::CashSpec)::Cash
    cash = _register_cash_asset!(acc.ledger, spec)
    _ensure_rates_size!(acc.exchange_rates, cash.index)
    cash
end

"""
Format a timestamp using the account's configured date format.
"""
@inline format_datetime(acc::Account, x::Dates.AbstractDateTime) = Dates.format(x, acc.datetime_format)
@inline format_datetime(acc::Account, x::Dates.Date) = Dates.format(x, acc.date_format)

"""
Generates the next order ID sequence value for the account.
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
    isless(amount, zero(amount)) && throw(ArgumentError("Deposit amount must be non-negative."))
    cash = cash_asset(acc.ledger, symbol)
    deposit!(acc, cash, amount)
end

function deposit!(
    acc::Account{TTime},
    cash::Cash,
    amount::Real,
) where {TTime<:Dates.AbstractTime}
    isless(amount, zero(amount)) && throw(ArgumentError("Deposit amount must be non-negative."))

    idx = cash.index
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
    if acc.mode == AccountMode.Cash
        @inbounds post_balance = acc.ledger.balances[idx] - amount
        post_balance < 0 && throw(ArgumentError("Withdrawal would overdraw cash balance for $(symbol)."))
        if acc.margining_style == MarginingStyle.PerCurrency
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

    if acc.margining_style == MarginingStyle.PerCurrency
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
    isless(amount, zero(amount)) && throw(ArgumentError("Withdraw amount must be non-negative."))
    amount_p = Price(amount)
    cash = cash_asset(acc.ledger, symbol)
    _withdraw_idx!(acc, cash.index, cash.symbol, amount_p)
end

@inline function withdraw!(
    acc::Account{TTime},
    cash::Cash,
    amount::Real,
) where {TTime<:Dates.AbstractTime}
    isless(amount, zero(amount)) && throw(ArgumentError("Withdraw amount must be non-negative."))
    amount_p = Price(amount)
    idx = cash.index
    _withdraw_idx!(acc, idx, cash.symbol, amount_p)
end

"""
Registers a new instrument in the account and returns it.

An instrument can only be registered once.
Before trading any instrument, it must be registered in the account.
"""
function register_instrument!(
    acc::Account{TTime},
    inst::Instrument{TTime}
) where {TTime<:Dates.AbstractTime}
    # ensure instrument is not being reused
    inst.index > 0 && throw(ArgumentError("Instrument $(inst.symbol) is already registered (index > 0)"))

    # ensure instrument symbol is not already registered
    if any(x -> x.inst.symbol == inst.symbol, acc.positions)
        throw(ArgumentError("Instrument $(inst.symbol) already registered"))
    end

    # sanity check instrument parameters
    validate_instrument(inst)

    # ensure cash assets are registered in account
    if !has_cash_asset(acc.ledger, inst.quote_symbol)
        throw(ArgumentError("Quote cash asset '$(inst.quote_symbol)' for instrument '$(inst.symbol)' not registered in account"))
    end
    if !has_cash_asset(acc.ledger, inst.settle_symbol)
        throw(ArgumentError("Settlement cash asset '$(inst.settle_symbol)' for instrument '$(inst.symbol)' not registered in account"))
    end
    if !has_cash_asset(acc.ledger, inst.margin_symbol)
        throw(ArgumentError("Margin cash asset '$(inst.margin_symbol)' for instrument '$(inst.symbol)' not registered in account"))
    end

    # set cash indexes for fast array indexing and margin calculations
    inst.quote_cash_index = cash_index(acc.ledger, inst.quote_symbol)
    inst.settle_cash_index = cash_index(acc.ledger, inst.settle_symbol)
    inst.margin_cash_index = cash_index(acc.ledger, inst.margin_symbol)

    # set asset index for fast array indexing and hashing
    inst.index = length(acc.positions) + 1

    # create empty position for the instrument
    push!(acc.positions, Position{TTime}(inst.index, inst))

    inst
end

"""
Internal: synchronize broker-provided borrow/lend rates for all cash assets.
"""
function _sync_broker_interest_rates!(
    acc::Account{TTime,NoOpBroker},
    dt::TTime,
) where {TTime<:Dates.AbstractTime}
    acc
end

function _sync_broker_interest_rates!(
    acc::Account{TTime,TBroker},
    dt::TTime,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    ledger = acc.ledger
    @inbounds for cash in ledger.cash
        idx = cash.index
        balance = ledger.balances[idx]
        borrow_rate, lend_rate = broker_interest_rates(acc.broker, cash.symbol, dt, balance)
        ledger.interest_borrow_rate[idx] = borrow_rate
        ledger.interest_lend_rate[idx] = lend_rate
    end

    acc
end

"""
Internal: synchronize broker-provided interest rates at `dt`.
"""
@inline function _sync_broker_state!(
    acc::Account{TTime,TBroker},
    dt::TTime,
) where {TTime<:Dates.AbstractTime,TBroker<:AbstractBroker}
    _sync_broker_interest_rates!(acc, dt)
    acc
end

"""
Returns the position object of the given instrument in the account.
"""
@inline function get_position(acc::Account{TTime}, inst::Instrument{TTime}) where {TTime<:Dates.AbstractTime}
    @inbounds acc.positions[inst.index]
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
@inline cash_balance(acc::Account, cash::Cash) = @inbounds acc.ledger.balances[cash.index]

"""
Returns the equity value of the provided cash asset in the account.

Equity is calculated as your cash balance +/- the floating profit/loss
of your open positions in the same currency, not including closing commission.
"""
@inline equity(acc::Account, cash::Cash) = @inbounds acc.ledger.equities[cash.index]

"""
Initial margin currently used in the given currency.
"""
@inline init_margin_used(acc::Account, cash::Cash)::Price = @inbounds acc.ledger.init_margin_used[cash.index]

"""
Maintenance margin currently used in the given currency.
"""
@inline maint_margin_used(acc::Account, cash::Cash)::Price = @inbounds acc.ledger.maint_margin_used[cash.index]

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
    _get_rate_base_ccy_idx(acc, cash.index)
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

@inline function update_rate!(
    acc::Account,
    from_idx::Int,
    to_idx::Int,
    rate::Real,
)
    _ensure_account_cash_index(acc, from_idx)
    _ensure_account_cash_index(acc, to_idx)
    update_rate!(acc.exchange_rates, from_idx, to_idx, rate)
end

@inline function update_rate!(
    acc::Account,
    from::Cash,
    to::Cash,
    rate::Real,
)
    update_rate!(acc.exchange_rates, from, to, rate)
end

@inline function update_rate!(
    acc::Account,
    from_symbol::Symbol,
    to_symbol::Symbol,
    rate::Real,
)
    from = cash_asset(acc.ledger, from_symbol)
    to = cash_asset(acc.ledger, to_symbol)
    update_rate!(acc.exchange_rates, from, to, rate)
end

@inline function get_rate(
    acc::Account,
    from_idx::Int,
    to_idx::Int;
    allow_nan::Bool=false,
)
    _ensure_account_cash_index(acc, from_idx)
    _ensure_account_cash_index(acc, to_idx)
    get_rate(acc.exchange_rates, from_idx, to_idx; allow_nan=allow_nan)
end

@inline function get_rate(
    acc::Account,
    from::Cash,
    to::Cash;
    allow_nan::Bool=false,
)
    get_rate(acc.exchange_rates, from, to; allow_nan=allow_nan)
end

@inline function get_rate(
    acc::Account,
    from_symbol::Symbol,
    to_symbol::Symbol;
    allow_nan::Bool=false,
)
    from = cash_asset(acc.ledger, from_symbol)
    to = cash_asset(acc.ledger, to_symbol)
    get_rate(acc.exchange_rates, from, to; allow_nan=allow_nan)
end

# ---------------------------------------------------------
# Currency/unit helpers (see currency/unit semantics note in `contract_math.jl`)

"""
Retrieve the `Cash` object for the instrument quote currency without allocations.
"""
@inline quote_cash(acc::Account, inst::Instrument) = @inbounds acc.ledger.cash[inst.quote_cash_index]

"""
Retrieve the `Cash` object for the instrument settlement currency without allocations.
"""
@inline settle_cash(acc::Account, inst::Instrument) = @inbounds acc.ledger.cash[inst.settle_cash_index]

"""
Retrieve the `Cash` object for the instrument margin currency without allocations.
"""
@inline margin_cash(acc::Account, inst::Instrument) = @inbounds acc.ledger.cash[inst.margin_cash_index]

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
    amount_quote * _get_rate_idx(acc, inst.quote_cash_index, inst.settle_cash_index)
end

"""
Convert a settlement-currency amount back into the instrument quote currency.
Inverse of `to_settle`; useful for round-trip tests and diagnostics.
"""
@inline function to_quote(acc::Account, inst::Instrument, amount_settle::Price)::Price
    amount_settle * _get_rate_idx(acc, inst.settle_cash_index, inst.quote_cash_index)
end

"""
Convert a quote-currency amount into the instrument margin currency.
"""
@inline function to_margin(acc::Account, inst::Instrument, amount_quote::Price)::Price
    amount_quote * _get_rate_idx(acc, inst.quote_cash_index, inst.margin_cash_index)
end

"""
Convert a margin-currency amount back into the instrument quote currency.
Inverse of `to_margin`; useful for diagnostics.
"""
@inline function to_quote_from_margin(acc::Account, inst::Instrument, amount_margin::Price)::Price
    amount_margin * _get_rate_idx(acc, inst.margin_cash_index, inst.quote_cash_index)
end

"""
Convert a settlement-currency amount into the account base currency.
"""
@inline function to_base(acc::Account, settle_idx::Int, amount_settle::Price)::Price
    amount_settle * _get_rate_base_ccy_idx(acc, settle_idx)
end

@inline to_base(acc::Account, cash::Cash, amount_settle::Price)::Price = to_base(acc, cash.index, amount_settle)
