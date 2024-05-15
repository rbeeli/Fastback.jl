using Dates
using PrettyTables

"""
Abstract type for exchange rates.

Exchange rates are used to convert between different assets,
for example to convert account assets to the account's base currency.
"""
abstract type ExchangeRates{AData} end

# ---------------------------------------------------------

"""
Dummy exchange rate implementation which always returns 1.0 as exchange rate.
"""
struct OneExchangeRates{AData} <: ExchangeRates{AData} end

"""
Get the exchange rate between two assets.

For `OneExchangeRates`, the exchange rate is always 1.0.
"""
@inline get_rate(er::OneExchangeRates, from::Asset, to::Asset) = 1.0

# ---------------------------------------------------------

"""
Exchange rate implementation which uses a dictionary
to store the current exchange rates.
"""
mutable struct SpotExchangeRates{AData} <: ExchangeRates{AData}
    const rates::Vector{Vector{Float64}} # rates[from][to] using internal index
    const indices::Dict{Asset{AData},UInt} # asset -> index
    const assets::Vector{Asset{AData}}

    function SpotExchangeRates{AData}() where {AData}
        new{AData}(
            Vector{Vector{Float64}}(),
            Dict{Asset{AData},Int}(),
            Vector{Asset{AData}}()
        )
    end
end

function add_asset!(er::SpotExchangeRates, asset::Asset{AData}) where {AData}
    !haskey(er.indices, asset) || throw(ArgumentError("Exchange asset $(asset.symbol) already added"))

    push!(er.assets, asset)

    # add asset to internal index cache
    er.indices[asset] = length(er.indices) + 1

    # add new rates vector row in rates matrix
    push!(er.rates, fill(NaN, length(er.rates)))

    # add new rates column in rates matrix
    for rates in er.rates
        push!(rates, NaN)
    end

    # set self-exchange rate to 1.0
    update_rate!(er, asset, asset, 1.0)

    nothing
end

"""
Get the exchange rate between two assets according to the current rates.
"""
@inline get_rate(er::SpotExchangeRates, from::Asset, to::Asset) =
    @inbounds er.rates[er.indices[from]][er.indices[to]]

"""
Builds an exchange rate matrix for all assets.

Rows represent the asset to convert from, columns the asset to convert to.
"""
function get_rates_matrix(er::SpotExchangeRates)
    mat = fill(NaN, length(er.assets), length(er.assets))
    for f in 1:length(er.assets)
        for t in 1:length(er.assets)
            mat[f, t] = get_rate(er, er.assets[f], er.assets[t])
        end
    end
    mat
end

"""
Update the exchange rate between two assets.
"""
function update_rate!(er::SpotExchangeRates, from::Asset, to::Asset, rate::Real)
    @inbounds er.rates[er.indices[from]][er.indices[to]] = Float64(rate)
    @inbounds er.rates[er.indices[to]][er.indices[from]] = 1.0/Float64(rate)
    nothing
end

function Base.show(io::IO, er::SpotExchangeRates)
    length(er.assets) > 0 || return println(io, "No spot exchange rates available")
    pretty_table(
        io,
        get_rates_matrix(er),
        ;
        header=getfield.(er.assets, :symbol),
        row_labels=getfield.(er.assets, :symbol),
        compact_printing=true)
end
