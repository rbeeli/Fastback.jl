mutable struct Account{TTime<:Dates.AbstractTime, TER<:ExchangeRates}
    const mode::AccountMode.T
    const cash::Vector{Cash}
    const cash_by_symbol::Dict{Symbol,Cash}
    const exchange_rates::TER
    base_currency::Symbol
    base_ccy_index::Int
    const balances::Vector{Price}           # balance per cash currency
    const equities::Vector{Price}           # equity per cash currency
    const interest_borrow_rate::Vector{Price} # borrow interest per cash currency
    const interest_lend_rate::Vector{Price} # lend interest per cash currency
    const init_margin_used::Vector{Price}   # initial margin used per cash currency
    const maint_margin_used::Vector{Price}  # maintenance margin used per cash currency
    const positions::Vector{Position{TTime}}
    const trades::Vector{Trade{TTime}}
    order_sequence::Int
    trade_sequence::Int
    last_interest_dt::TTime
    const date_format::Dates.DateFormat

    function Account(
        ;
        base_currency::Symbol,
        time_type::Type{TTime}=DateTime,
        mode::AccountMode.T=AccountMode.Cash,
        date_format=dateformat"yyyy-mm-dd HH:MM:SS",
        order_sequence=0,
        trade_sequence=0,
        exchange_rates::TER=OneExchangeRates(),
    ) where {TTime<:Dates.AbstractTime, TER<:ExchangeRates}
        new{TTime,TER}(
            mode,
            Vector{Cash}(), # cash
            Dict{Symbol,Cash}(), # cash_by_symbol
            exchange_rates,
            base_currency,
            0, # base_ccy_index
            Vector{Price}(), # balances
            Vector{Price}(), # equities
            Vector{Price}(), # interest_borrow_rate
            Vector{Price}(), # interest_lend_rate
            Vector{Price}(), # init_margin_used
            Vector{Price}(), # maint_margin_used
            Vector{Position{TTime}}(), # positions
            Vector{Trade{TTime}}(), # trades
            order_sequence,
            trade_sequence,
            TTime(0), # last_interest_dt
            date_format
        )
    end
end

@inline format_datetime(acc::Account, x) = Dates.format(x, acc.date_format)
@inline oid!(acc::Account) = acc.order_sequence += 1
@inline tid!(acc::Account) = acc.trade_sequence += 1
@inline exchange_rates(acc::Account)::ExchangeRates = acc.exchange_rates

"""
Returns a `Cash` object with the given symbol.

Cash objects must be registered first in the account before
they can be accessed, see `register_cash_asset!`.
"""
@inline cash_asset(acc::Account, symbol::Symbol) = @inbounds acc.cash_by_symbol[symbol]

"""
Checks if the account has the given cash symbol registered.
"""
@inline has_cash_asset(acc::Account, symbol::Symbol) = haskey(acc.cash_by_symbol, symbol)

"""
Registers a new cash asset in the account.

Cash is a liquid coin or currency that is used to trade instruments with, e.g. USD, CHF, BTC, ETH.
When funding the account, the funds are added to the balance of the corresponding cash asset.
"""
function register_cash_asset!(
    acc::Account{TTime},
    cash::Cash
) where {TTime<:Dates.AbstractTime}
    !has_cash_asset(acc, cash.symbol) || throw(ArgumentError("Cash with symbol '$(cash.symbol)' already registered."))

    # set index for fast array indexing and hashing
    cash.index = length(acc.cash) + 1

    add_asset!(acc.exchange_rates, cash)

    push!(acc.cash, cash)
    acc.cash_by_symbol[cash.symbol] = cash
    push!(acc.balances, zero(Price))
    push!(acc.equities, zero(Price))
    push!(acc.interest_borrow_rate, zero(Price))
    push!(acc.interest_lend_rate, zero(Price))
    push!(acc.init_margin_used, zero(Price))
    push!(acc.maint_margin_used, zero(Price))

    # set base cash when its currency is registered
    if cash.symbol == acc.base_currency
        acc.base_ccy_index = cash.index
    end
end

@inline function _adjust_cash!(
    acc::Account{TTime},
    cash::Cash,
    amount::Real
) where {TTime<:Dates.AbstractTime}
    # register cash object if not already registered
    has_cash_asset(acc, cash.symbol) || register_cash_asset!(acc, cash)

    # ensure cash object was registered
    cash.index > 0 || throw(ArgumentError("Cash with symbol '$(cash.symbol)' not registered."))

    # update balance and equity for the asset
    @inbounds begin
        acc.balances[cash.index] += Price(amount)
        acc.equities[cash.index] += Price(amount)
    end

    cash
end

"""
Deposits cash into the account balance.

Cash is a liquid coin or currency that is used to trade instruments with, e.g. USD, CHF, BTC, ETH.

The funds are added to the balance and equity of the corresponding cash asset.
Use `withdraw!` to reduce the balance again.
"""
function deposit!(
    acc::Account{TTime},
    cash::Cash,
    amount::Real
) where {TTime<:Dates.AbstractTime}
    isless(amount, zero(amount)) && throw(ArgumentError("Deposit amount must be non-negative."))
    _adjust_cash!(acc, cash, amount)
end

"""
Withdraws cash from the account balance.

The funds are subtracted from the balance and equity of the corresponding cash asset.
Use `deposit!` to fund an account.
"""
function withdraw!(
    acc::Account{TTime},
    cash::Cash,
    amount::Real
) where {TTime<:Dates.AbstractTime}
    isless(amount, zero(amount)) && throw(ArgumentError("Withdraw amount must be non-negative."))
    _adjust_cash!(acc, cash, -amount)
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
    # ensure instrument is not already registered
    if any(x -> x.inst.symbol == inst.symbol, acc.positions)
        throw(ArgumentError("Instrument $(inst.symbol) already registered"))
    end

    # sanity check instrument parameters
    validate_instrument(inst)

    # ensure quote cash asset is registered in account
    if !has_cash_asset(acc, inst.quote_symbol)
        throw(ArgumentError("Quote cash asset '$(inst.quote_symbol)' for instrument '$(inst.symbol)' not registered in account"))
    end

    # set quote cash index for fast array indexing and margin calculations
    quote_cash_index = cash_asset(acc, inst.quote_symbol).index
    inst.quote_cash_index = quote_cash_index

    # set asset index for fast array indexing and hashing
    inst.index = length(acc.positions) + 1

    # create empty position for the instrument
    push!(acc.positions, Position{TTime}(inst.index, inst))

    inst
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
@inline cash_balance(acc::Account, cash::Cash) = @inbounds acc.balances[cash.index]

"""
Returns the cash balance of the provided cash asset in the account.

Convenience method dispatching on the cash symbol instead of the `Cash` object.
The returned value does not include the P&L value of open positions.
"""
@inline cash_balance(acc::Account, cash_symbol::Symbol) = cash_balance(acc, cash_asset(acc, cash_symbol))

"""
Returns the equity value of the provided cash asset in the account.

Equity is calculated as your cash balance +/- the floating profit/loss
of your open positions in the same currency, not including closing commission.
"""
@inline equity(acc::Account, cash::Cash) = @inbounds acc.equities[cash.index]

"""
Returns the equity value of the provided cash asset in the account.

Equity is calculated as your cash balance +/- the floating profit/loss
of your open positions in the same currency, not including closing commission.
"""
@inline equity(acc::Account, cash_symbol::Symbol) = equity(acc, cash_asset(acc, cash_symbol))

@inline init_margin_used(acc::Account, cash::Cash)::Price = @inbounds acc.init_margin_used[cash.index]
@inline init_margin_used(acc::Account, cash_symbol::Symbol)::Price = init_margin_used(acc, cash_asset(acc, cash_symbol))

@inline maint_margin_used(acc::Account, cash::Cash)::Price = @inbounds acc.maint_margin_used[cash.index]
@inline maint_margin_used(acc::Account, cash_symbol::Symbol)::Price = maint_margin_used(acc, cash_asset(acc, cash_symbol))

@inline available_funds(acc::Account, cash::Cash) = equity(acc, cash) - init_margin_used(acc, cash)
@inline available_funds(acc::Account, cash_symbol::Symbol) = available_funds(acc, cash_asset(acc, cash_symbol))

@inline excess_liquidity(acc::Account, cash::Cash) = equity(acc, cash) - maint_margin_used(acc, cash)
@inline excess_liquidity(acc::Account, cash_symbol::Symbol) = excess_liquidity(acc, cash_asset(acc, cash_symbol))

# ---------------------------------------------------------
# Base currency helpers

@inline has_base_ccy(acc::Account)::Bool = acc.base_ccy_index > 0
@inline function cash_base_ccy(acc::Account)::Cash
    acc.base_ccy_index > 0 || throw(ArgumentError("Base currency cash asset is not registered in the account."))
    @inbounds acc.cash[acc.base_ccy_index]
end

@inline function get_rate_base_ccy(acc::Account, i::Int)::Float64
    acc.base_ccy_index > 0 || throw(ArgumentError("Base currency cash asset is not registered in the account."))
    i == acc.base_ccy_index && return 1.0
    from = @inbounds acc.cash[i]
    to = cash_base_ccy(acc)
    r = get_rate(acc.exchange_rates, from, to)
    if isnan(r)
        throw(ArgumentError("Missing FX rate from $(from.symbol) to base $(to.symbol)."))
    end
    r
end

@inline function get_rate_base_ccy(acc::Account, cash::Cash)::Float64
    idx = cash.index
    idx > 0 || throw(ArgumentError("Cash with symbol '$(cash.symbol)' not registered in account."))
    get_rate_base_ccy(acc, idx)
end

function equity_base_ccy(acc::Account)::Price
    has_base_ccy(acc) || throw(ArgumentError("Account base currency not set."))
    total = zero(Price)
    @inbounds for i in eachindex(acc.equities)
        val = acc.equities[i]
        iszero(val) && continue  # avoid 0 * NaN when rate is missing
        total += val * get_rate_base_ccy(acc, i)
    end
    total
end

function balance_base_ccy(acc::Account)::Price
    has_base_ccy(acc) || throw(ArgumentError("Account base currency not set."))
    total = zero(Price)
    @inbounds for i in eachindex(acc.balances)
        val = acc.balances[i]
        iszero(val) && continue
        total += val * get_rate_base_ccy(acc, i)
    end
    total
end

function init_margin_used_base_ccy(acc::Account)::Price
    has_base_ccy(acc) || throw(ArgumentError("Account base currency not set."))
    total = zero(Price)
    @inbounds for i in eachindex(acc.init_margin_used)
        val = acc.init_margin_used[i]
        iszero(val) && continue
        total += val * get_rate_base_ccy(acc, i)
    end
    total
end

function maint_margin_used_base_ccy(acc::Account)::Price
    has_base_ccy(acc) || throw(ArgumentError("Account base currency not set."))
    total = zero(Price)
    @inbounds for i in eachindex(acc.maint_margin_used)
        val = acc.maint_margin_used[i]
        iszero(val) && continue
        total += val * get_rate_base_ccy(acc, i)
    end
    total
end

@inline available_funds_base_ccy(acc::Account)::Price = equity_base_ccy(acc) - init_margin_used_base_ccy(acc)
@inline excess_liquidity_base_ccy(acc::Account)::Price = equity_base_ccy(acc) - maint_margin_used_base_ccy(acc)
