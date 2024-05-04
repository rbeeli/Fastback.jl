mutable struct Account{OData,IData,AData,ER<:ExchangeRates}
    const base_asset::Asset{AData}
    const assets::Vector{Asset{AData}}
    const assets_by_symbol::Dict{Symbol,Asset{AData}}
    const balances::Vector{Price}           # balance per asset
    const equities::Vector{Price}           # equity per asset
    const positions::Vector{Position{OData,IData}}
    const trades::Vector{Trade{OData,IData}}
    const exchange_rates::ER
    order_sequence::Int
    trade_sequence::Int
    const date_format::Dates.DateFormat

    function Account{OData,IData}(
        base_asset::Asset{AData}
        ;
        date_format=dateformat"yyyy-mm-dd HH:MM:SS",
        order_sequence::Int=0,
        trade_sequence::Int=0,
        exchange_rates::ER=OneExchangeRates{AData}()
    ) where {OData,IData,AData,ER<:ExchangeRates}
        new{OData,IData,AData,ER}(
            base_asset,
            Vector{Asset{AData}}(), # assets
            Dict{Symbol,Asset{AData}}(), # assets_by_symbol
            Vector{Price}(), # balances
            Vector{Price}(), # equities
            Vector{Position{OData,IData}}(), # positions
            Vector{Trade{OData,IData}}(), # trades
            exchange_rates,
            order_sequence,
            trade_sequence,
            date_format
        )
    end
end

@inline format_base(acc::Account, value) = format_value(acc.base_asset, value)
@inline format_date(acc::Account, x) = Dates.format(x, acc.date_format)
@inline oid!(acc::Account) = acc.order_sequence += 1
@inline tid!(acc::Account) = acc.trade_sequence += 1

"""
Returns the asset with the given symbol.

Assets must first be registered in the account before they can be accessed,
see `register_asset!`.
"""
@inline get_asset(acc::Account, symbol::Symbol) = @inbounds acc.assets_by_symbol[symbol]

"""
Returns the balance of the given asset in the account.

This does not include the equity of open positions, i.e. unrealized P&L.
"""
@inline get_asset_value(acc::Account, asset::Asset) = @inbounds acc.balances[asset.index]

"""
Registers a new asset in the account.

An asset is a coin or currency that is used to trade instruments with, e.g. USD, CHF, BTC, ETH.
When funding the trading account, the funds are added to the balance of the corresponding asset.
"""
function register_asset!(acc::Account{OData,IData,AData,ER}, asset::Asset{AData}) where {OData,IData,AData,ER}
    if asset.index <= length(acc.assets)
        throw(ArgumentError("Asset $(asset.symbol) already registered"))
    end

    if asset.index != length(acc.assets) + 1
        throw(ArgumentError("Asset indices must be consecutive starting from 1"))
    end

    if haskey(acc.assets_by_symbol, asset.symbol)
        throw(ArgumentError("Asset $(asset.symbol) already registered"))
    end

    push!(acc.assets, asset)
    acc.assets_by_symbol[asset.symbol] = asset
    push!(acc.balances, zero(Price))
    push!(acc.equities, zero(Price))
end

"""
Adds funds to the account.

The funds are added to the balance of the corresponding asset.
An asset is a coin or currency that is used to trade instruments with, e.g. USD, CHF, BTC, ETH.
"""
function add_funds!(acc::Account{OData,IData,AData,ER}, asset::Asset{AData}, value::Price) where {OData,IData,AData,ER}
    # ensure funding amount is not negative
    if value < zero(Price)
        throw(ArgumentError("Funds value cannot be negative, got $value"))
    end

    # register asset if not already registered
    if asset.index > length(acc.balances)
        register_asset!(acc, asset)
    end

    @inbounds acc.balances[asset.index] += value
    @inbounds acc.equities[asset.index] += value

    asset
end

"""
Registers a new instrument in the account and returns it.

An instrument can only be registered once.
Before trading any instrument, it must be registered in the account.
"""
function register_instrument!(
    acc::Account{OData,IData,AData,ER},
    inst::Instrument{OData}
) where {OData,IData,AData,ER}
    if inst.index <= length(acc.positions)
        throw(ArgumentError("Instrument $(inst.symbol) already registered"))
    end

    if inst.index != length(acc.positions) + 1
        throw(ArgumentError("Instrument indices must be consecutive starting from 1"))
    end

    push!(acc.positions, Position{OData}(inst.index, inst))

    inst
end

"""
Computes the total account balance in the base currency.

This figures does not include the equity of open positions.
"""
@inline function total_balance(acc::Account)
    total = 0.0
    for asset in acc.assets
        er = get_exchange_rate(acc.exchange_rates, asset, acc.base_asset)
        total += er * @inbounds acc.balances[asset.index]
    end
    total
end

"""
Computes the total account equity in the base currency.

This figure includes the equity of open positions and is
approximately equal to the total balance plus the unrealized P&L,
not including closing fees.
"""
@inline function total_equity(acc::Account)
    total = 0.0
    for asset in acc.assets
        er = get_exchange_rate(acc.exchange_rates, asset, acc.base_asset)
        total += er * @inbounds acc.equities[asset.index]
    end
    total
end

@inline function get_position(acc::Account, inst::Instrument)
    @inbounds acc.positions[inst.index]
end

@inline function is_exposed_to(acc::Account, inst::Instrument)
    has_exposure(get_position(acc, inst))
end

@inline function is_exposed_to(acc::Account, inst::Instrument, dir::TradeDir.T)
    trade_dir(get_position(acc, inst)) == sign(dir)
end

# @inline total_pnl_net(acc::Account) = sum(map(pnl_net, acc.closed_positions))
# @inline total_pnl_gross(acc::Account) = sum(map(pnl_gross, acc.closed_positions))

# @inline count_winners_net(acc::Account) = count(map(x -> pnl_net(x) > 0.0, acc.closed_positions))
# @inline count_winners_gross(acc::Account) = count(map(x -> pnl_gross(x) > 0.0, acc.closed_positions))

@inline function update_pnl!(acc::Account, pos::Position, close_price)
    # update P&L and account equity using delta of old and new P&L
    new_pnl = calc_pnl(pos, close_price)
    pnl_delta = new_pnl - pos.pnl
    asset = get_asset(acc, pos.inst.quote_asset)
    @inbounds acc.equities[asset.index] += pnl_delta
    pos.pnl = new_pnl
    return
end

@inline function update_pnl!(acc::Account, inst::Instrument, close_price)
    update_pnl!(acc, get_position(acc, inst), close_price)
end
