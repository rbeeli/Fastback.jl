mutable struct Account{TTime<:Dates.AbstractTime,OData,IData,CData}
    const cash::Vector{Cash{CData}}
    const cash_by_symbol::Dict{Symbol,Cash{CData}}
    const balances::Vector{Price}           # balance per cash currency
    const equities::Vector{Price}           # equity per cash currency
    const init_margin_used::Vector{Price}   # initial margin used per cash currency
    const maint_margin_used::Vector{Price}  # maintenance margin used per cash currency
    const positions::Vector{Position{TTime,OData,IData}}
    const trades::Vector{Trade{TTime,OData,IData}}
    order_sequence::Int
    trade_sequence::Int
    const date_format::Dates.DateFormat

    function Account(
        ;
        date_format=dateformat"yyyy-mm-dd HH:MM:SS",
        order_sequence=0,
        trade_sequence=0,
        odata::Type{OData}=Nothing,
        idata::Type{IData}=Nothing,
        cdata::Type{CData}=Nothing,
        time_type::Type{TTime}=DateTime,
    ) where {TTime<:Dates.AbstractTime,OData,IData,CData}
        new{TTime,OData,IData,CData}(
            Vector{Cash{CData}}(), # cash
            Dict{Symbol,Cash{CData}}(), # cash_by_symbol
            Vector{Price}(), # balances
            Vector{Price}(), # equities
            Vector{Price}(), # init_margin_used
            Vector{Price}(), # maint_margin_used
            Vector{Position{TTime,OData,IData}}(), # positions
            Vector{Trade{TTime,OData,IData}}(), # trades
            order_sequence,
            trade_sequence,
            date_format
        )
    end
end

@inline format_datetime(acc::Account, x) = Dates.format(x, acc.date_format)
@inline oid!(acc::Account) = acc.order_sequence += 1
@inline tid!(acc::Account) = acc.trade_sequence += 1

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
    acc::Account{TTime,OData,IData,CData},
    cash::Cash{CData}
) where {TTime<:Dates.AbstractTime,OData,IData,CData}
    !has_cash_asset(acc, cash.symbol) || throw(ArgumentError("Cash with symbol '$(cash.symbol)' already registered."))

    # set index for fast array indexing and hashing
    cash.index = length(acc.cash) + 1

    push!(acc.cash, cash)
    acc.cash_by_symbol[cash.symbol] = cash
    push!(acc.balances, zero(Price))
    push!(acc.equities, zero(Price))
    push!(acc.init_margin_used, zero(Price))
    push!(acc.maint_margin_used, zero(Price))
end

@inline function _adjust_cash!(
    acc::Account{TTime,OData,IData,CData},
    cash::Cash{CData},
    amount::Real
) where {TTime<:Dates.AbstractTime,OData,IData,CData}
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
    acc::Account{TTime,OData,IData,CData},
    cash::Cash{CData},
    amount::Real
) where {TTime<:Dates.AbstractTime,OData,IData,CData}
    isless(amount, zero(amount)) && throw(ArgumentError("Deposit amount must be non-negative."))
    _adjust_cash!(acc, cash, amount)
end

"""
Withdraws cash from the account balance.

The funds are subtracted from the balance and equity of the corresponding cash asset.
Use `deposit!` to fund an account.
"""
function withdraw!(
    acc::Account{TTime,OData,IData,CData},
    cash::Cash{CData},
    amount::Real
) where {TTime<:Dates.AbstractTime,OData,IData,CData}
    isless(amount, zero(amount)) && throw(ArgumentError("Withdraw amount must be non-negative."))
    _adjust_cash!(acc, cash, -amount)
end

"""
Registers a new instrument in the account and returns it.

An instrument can only be registered once.
Before trading any instrument, it must be registered in the account.
"""
function register_instrument!(
    acc::Account{TTime,OData,IData,CData},
    inst::Instrument{IData}
) where {TTime<:Dates.AbstractTime,OData,IData,CData}
    if any(x -> x.inst.symbol == inst.symbol, acc.positions)
        throw(ArgumentError("Instrument $(inst.symbol) already registered"))
    end

    quote_cash_index = cash_asset(acc, inst.quote_symbol).index

    # set asset index for fast array indexing and hashing
    inst.index = length(acc.positions) + 1
    inst.quote_cash_index = quote_cash_index

    push!(acc.positions, Position{TTime,OData}(inst.index, inst))

    inst
end

"""
Returns the position object of the given instrument in the account.
"""
@inline function get_position(acc::Account, inst::Instrument)
    @inbounds acc.positions[inst.index]
end

"""
Determines if the account has non-zero exposure to the given instrument.
"""
@inline function is_exposed_to(acc::Account, inst::Instrument)
    has_exposure(get_position(acc, inst))
end

"""
Determines if the account has non-zero exposure to the given instrument
in the given direction (`Buy`, `Sell`).
"""
@inline function is_exposed_to(acc::Account, inst::Instrument, dir::TradeDir.T)
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
