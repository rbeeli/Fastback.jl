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
@inline get_rate(er::OneExchangeRates, from::Cash, to::Cash; allow_nan::Bool=false) = 1.0

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
    const rates::Vector{Vector{Float64}} # rates[from_idx][to_idx]
    const assets::Vector{Cash}
    const asset_by_symbol::Dict{Symbol,Int}

    function SpotExchangeRates()
        new(
            Vector{Vector{Float64}}(),
            Vector{Cash}(),
            Dict{Symbol,Int}(),
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
    haskey(er.asset_by_symbol, cash.symbol) &&
        throw(ArgumentError("Exchange cash asset '$(cash.symbol)' was already added."))

    idx = length(er.assets) + 1
    cash.index == idx ||
        throw(ArgumentError("Exchange cash asset '$(cash.symbol)' has index $(cash.index), expected $(idx)."))
    push!(er.assets, cash)
    er.asset_by_symbol[cash.symbol] = idx

    _ensure_rates_size!(er, idx)
    @inbounds er.rates[idx][idx] = 1.0

    return idx
end

"""
Get the exchange rate between two assets according to the current rates.
"""
@inline function _get_rate_idx(er::SpotExchangeRates, from_idx::Int, to_idx::Int; allow_nan::Bool=false)
    rate = @inbounds er.rates[from_idx][to_idx]
    if isnan(rate) && !allow_nan
        from = @inbounds er.assets[from_idx]
        to = @inbounds er.assets[to_idx]
        throw(ArgumentError("No exchange rate available from $(from.symbol) to $(to.symbol)."))
    end
    rate
end

@inline function get_rate(er::SpotExchangeRates, from::Cash, to::Cash; allow_nan::Bool=false)
    _get_rate_idx(er, from.index, to.index; allow_nan=allow_nan)
end

"""
Builds an exchange rate matrix for all assets.

Rows represent the asset to convert from, columns the asset to convert to.
"""
function get_rates_matrix(er::SpotExchangeRates)
    mat = fill(NaN, length(er.assets), length(er.assets))
    for f in 1:length(er.assets)
        for t in 1:length(er.assets)
            @inbounds mat[f, t] = _get_rate_idx(er, f, t, allow_nan=true)
        end
    end
    mat
end

"""
Update the exchange rate between two assets.
"""
function update_rate!(er::SpotExchangeRates, from::Cash, to::Cash, rate::Real)
    isfinite(rate) && rate > 0 || throw(ArgumentError("Exchange rate must be a positive finite number."))
    r = Float64(rate)
    from_idx = from.index
    to_idx = to.index
    @inbounds er.rates[from_idx][to_idx] = r
    @inbounds er.rates[to_idx][from_idx] = 1.0 / r
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
