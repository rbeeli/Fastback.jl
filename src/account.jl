import Format
using Tables

mutable struct Account{OData,IData,CData}
    const cash::Vector{Cash{CData}}
    const cash_by_symbol::Dict{Symbol,Cash{CData}}
    const balances::Vector{Price}           # balance per cash currency
    const equities::Vector{Price}           # equity per cash currency
    const positions::Vector{Position{OData,IData}}
    const trades::Vector{Trade{OData,IData}}
    order_sequence::Int
    trade_sequence::Int
    const date_format::Dates.DateFormat

    function Account(
        date_format=dateformat"yyyy-mm-dd HH:MM:SS",
        order_sequence=0,
        trade_sequence=0
        ;
        odata::Type{OData}=Nothing,
        idata::Type{IData}=Nothing,
        cdata::Type{CData}=Nothing
    ) where {OData,IData,CData}
        new{OData,IData,CData}(
            Vector{Cash{CData}}(), # cash
            Dict{Symbol,Cash{CData}}(), # cash_by_symbol
            Vector{Price}(), # balances
            Vector{Price}(), # equities
            Vector{Position{OData,IData}}(), # positions
            Vector{Trade{OData,IData}}(), # trades
            order_sequence,
            trade_sequence,
            date_format
        )
    end
end

@inline format_date(acc::Account, x) = Dates.format(x, acc.date_format)
@inline oid!(acc::Account) = acc.order_sequence += 1
@inline tid!(acc::Account) = acc.trade_sequence += 1

"""
Returns a `Cash` object with the given symbol.

Cash objects must be registered first in the account before
they can be accessed, see `register_cash!`.
"""
@inline cash_object(acc::Account, symbol::Symbol) = @inbounds acc.cash_by_symbol[symbol]

"""
Checks if the account has the given cash symbol registered.
"""
@inline hash_cash_symbol(acc::Account, symbol::Symbol) = haskey(acc.cash_by_symbol, symbol)

"""
Registers a new cash asset in the account.

Cash is a liquid coin or currency that is used to trade instruments with, e.g. USD, CHF, BTC, ETH.
When funding the account, the funds are added to the balance of the corresponding cash asset.
"""
function register_cash!(acc::Account{OData,IData,CData}, cash::Cash{CData}) where {OData,IData,CData}
    !hash_cash_symbol(acc, cash.symbol) || throw(ArgumentError("Cash with symbol '$(cash.symbol)' already registered."))

    # set index for fast array indexing and hashing
    cash.index = length(acc.cash) + 1

    push!(acc.cash, cash)
    acc.cash_by_symbol[cash.symbol] = cash
    push!(acc.balances, zero(Price))
    push!(acc.equities, zero(Price))
end

"""
Adds cash to the account balance.

Cash is a liquid coin or currency that is used to trade instruments with, e.g. USD, CHF, BTC, ETH.

The funds are added to the balance of the corresponding cash asset.
To withdraw (subtract) cash from the account, simply pass a negative value.
"""
function add_cash!(acc::Account{OData,IData,CData}, cash::Cash{CData}, value::Real) where {OData,IData,CData}
    # register cash object if not already registered
    hash_cash_symbol(acc, cash.symbol) || register_cash!(acc, cash)

    # ensure cash object was registered
    cash.index > 0 || throw(ArgumentError("Cash with symbol '$(cash.symbol)' not registered."))

    # update balance and equity for the asset
    @inbounds acc.balances[cash.index] += Price(value)
    @inbounds acc.equities[cash.index] += Price(value)

    cash
end

"""
Registers a new instrument in the account and returns it.

An instrument can only be registered once.
Before trading any instrument, it must be registered in the account.
"""
function register_instrument!(
    acc::Account{OData,IData,CData},
    inst::Instrument{IData}
) where {OData,IData,CData}
    if any(x -> x.inst.symbol == inst.symbol, acc.positions)
        throw(ArgumentError("Instrument $(inst.symbol) already registered"))
    end

    # set asset index for fast array indexing and hashing
    inst.index = length(acc.positions) + 1

    push!(acc.positions, Position{OData}(inst.index, inst))

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
    trade_dir(get_position(acc, inst)) == sign(dir)
end

"""
Returns the cash balance of the cash asset in the account.

The returned value does not include the P&L value of open positions.
"""
@inline cash(acc::Account, cash::Cash) = @inbounds acc.balances[cash.index]

"""
Returns the cash balance of the cash asset in the account.

The returned value does not include the P&L value of open positions.
"""
@inline cash(acc::Account, cash_symbol::Symbol) = cash(acc, cash_object(acc, cash_symbol))

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
@inline equity(acc::Account, cash_symbol::Symbol) = equity(acc, cash_object(acc, cash_symbol))

# Wrapper structures for Tables.jl interface
struct AccountBalances
    account::Account
end

struct AccountEquities
    account::Account
end

# Tables.jl interface for AccountBalances
Tables.istable(::Type{AccountBalances}) = true
Tables.rowaccess(::Type{AccountBalances}) = true
Tables.rows(x::AccountBalances) = [(symbol=c.symbol, balance=x.account.balances[c.index]) for c in x.account.cash]

Tables.schema(x::AccountBalances) = Tables.Schema((:symbol, :balance), Tuple{Symbol, Float64})

# Tables.jl interface for AccountEquities
Tables.istable(::Type{AccountEquities}) = true
Tables.rowaccess(::Type{AccountEquities}) = true
Tables.rows(x::AccountEquities) = [(symbol=c.symbol, equity=x.account.equities[c.index]) for c in x.account.cash]

Tables.schema(x::AccountEquities) = Tables.Schema((:symbol, :equity), Tuple{Symbol, Float64})

# Convenience functions to create Tables.jl compatible objects
balances_table(acc::Account) = AccountBalances(acc)
equities_table(acc::Account) = AccountEquities(acc)

# Direct Tables.jl interface for Account.balances and Account.equities
# These methods make acc.balances and acc.equities directly compatible with Tables.jl

# For Account.balances (Vector{Price}) in context of Account
struct AccountBalancesProperty{A <: Account}
    account::A
    balances::Vector{Float64}
end

struct AccountEquitiesProperty{A <: Account}
    account::A
    equities::Vector{Float64}
end

# Direct accessor functions that return Tables.jl compatible wrappers
balances(acc::Account) = AccountBalancesProperty(acc, getfield(acc, :balances))
equities(acc::Account) = AccountEquitiesProperty(acc, getfield(acc, :equities))

# Tables.jl interface for AccountBalancesProperty
Tables.istable(::Type{<:AccountBalancesProperty}) = true
Tables.rowaccess(::Type{<:AccountBalancesProperty}) = true
Tables.rows(x::AccountBalancesProperty) = [(symbol=c.symbol, balance=x.balances[c.index]) for c in x.account.cash]
Tables.schema(x::AccountBalancesProperty) = Tables.Schema((:symbol, :balance), Tuple{Symbol, Float64})

# Tables.jl interface for AccountEquitiesProperty
Tables.istable(::Type{<:AccountEquitiesProperty}) = true
Tables.rowaccess(::Type{<:AccountEquitiesProperty}) = true
Tables.rows(x::AccountEquitiesProperty) = [(symbol=c.symbol, equity=x.equities[c.index]) for c in x.account.cash]
Tables.schema(x::AccountEquitiesProperty) = Tables.Schema((:symbol, :equity), Tuple{Symbol, Float64})
