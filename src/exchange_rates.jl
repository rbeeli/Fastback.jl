using Dates
using PrettyTables

"""
Abstract type for exchange rates.

Exchange rates are used to convert between different assets,
for example to convert account assets to the account's base currency.
"""
abstract type ExchangeRates end

"""
Register a cash asset with the exchange rate provider.

Default implementation is a no-op.
"""
@inline add_asset!(er::ExchangeRates, cash::Cash) = nothing

# ---------------------------------------------------------

"""
Dummy exchange rate implementation which always returns 1.0 as exchange rate.
"""
struct OneExchangeRates <: ExchangeRates end

"""
Get the exchange rate between two assets.

For `OneExchangeRates`, the exchange rate is always 1.0.
"""
@inline get_rate(er::OneExchangeRates, from::Cash, to::Cash) = 1.0

"""
Register a cash asset with the exchange rate provider.

For `OneExchangeRates`, this is a no-op.
"""
@inline add_asset!(er::OneExchangeRates, cash::Cash) = nothing

# ---------------------------------------------------------

"""
Supports spot exchange rates between assets.
"""
mutable struct SpotExchangeRates <: ExchangeRates
    const rates::Vector{Vector{Float64}} # rates[from.index][to.index]
    const assets::Vector{Cash}

    function SpotExchangeRates()
        new(
            Vector{Vector{Float64}}(),
            Vector{Cash}()
        )
    end
end

@inline function _ensure_rates_size!(er::SpotExchangeRates, required::Int)
    current = length(er.rates)
    if required > current
        # extend existing rows with new NaN columns
        for row in er.rates
            append!(row, fill(NaN, required - length(row)))
        end

        # add new rows sized to the new dimension
        for _ in current+1:required
            push!(er.rates, fill(NaN, required))
        end
    end
    nothing
end

function add_asset!(er::SpotExchangeRates, cash::Cash)
    idx = cash.index
    idx > 0 || throw(ArgumentError("Cash with symbol '$(cash.symbol)' has no index set. Register it before adding exchange rates."))

    _ensure_rates_size!(er, idx)

    existing = er.rates[idx][idx]
    if !isnan(existing)
        throw(ArgumentError("Exchange cash asset '$(cash.symbol)' with index $(cash.index) was already added."))
    end

    push!(er.assets, cash)
    er.rates[idx][idx] = 1.0

    nothing
end

"""
Get the exchange rate between two assets according to the current rates.
"""
@inline get_rate(er::SpotExchangeRates, from::Cash, to::Cash) =
    @inbounds er.rates[from.index][to.index]

"""
Builds an exchange rate matrix for all assets.

Rows represent the asset to convert from, columns the asset to convert to.
"""
function get_rates_matrix(er::SpotExchangeRates)
    mat = fill(NaN, length(er.assets), length(er.assets))
    for f in 1:length(er.assets)
        for t in 1:length(er.assets)
            @inbounds mat[f, t] = get_rate(er, er.assets[f], er.assets[t])
        end
    end
    mat
end

"""
Update the exchange rate between two assets.
"""
function update_rate!(er::SpotExchangeRates, from::Cash, to::Cash, rate::Real)
    r = Float64(rate)
    @inbounds er.rates[from.index][to.index] = r
    @inbounds er.rates[to.index][from.index] = 1.0 / r
    return nothing
end

function Base.show(io::IO, er::SpotExchangeRates)
    length(er.assets) > 0 || return println(io, "No spot exchange rates available.")
    pretty_table(
        io,
        get_rates_matrix(er),
        ;
        column_labels=getfield.(er.assets, :symbol),
        row_labels=getfield.(er.assets, :symbol),
        compact_printing=true)
end
