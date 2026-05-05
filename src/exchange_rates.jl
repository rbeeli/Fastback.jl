using PrettyTables

"""
Supports spot exchange rates between cash assets by index.
"""
mutable struct ExchangeRates
    const rates::Vector{Vector{Float64}} # rates[from_idx][to_idx]

    function ExchangeRates()
        new(Vector{Vector{Float64}}())
    end
end

@inline function _ensure_rates_size!(er::ExchangeRates, required::Int)
    current = length(er.rates)
    if required > current
        delta = required - current

        # extend existing rows with new NaN columns
        for row in er.rates
            append!(row, fill(NaN, delta))
        end

        # add new rows sized to the new dimension
        for i in current+1:required
            row = fill(NaN, required)
            row[i] = 1.0
            push!(er.rates, row)
        end
    end

    @inbounds for i in 1:required
        isnan(er.rates[i][i]) && (er.rates[i][i] = 1.0)
    end
    nothing
end

@inline function _get_rate_idx_or_nan(er::ExchangeRates, from_idx::Int, to_idx::Int)
    from_idx == to_idx && return 1.0
    @inbounds er.rates[from_idx][to_idx]
end

@inline function _get_rate_idx(er::ExchangeRates, from_idx::Int, to_idx::Int)
    from_idx == to_idx && return 1.0
    rate = @inbounds er.rates[from_idx][to_idx]
    if isnan(rate)
        throw(ArgumentError("No exchange rate available from cash index $(from_idx) to $(to_idx)."))
    end
    rate
end

"""
Get the exchange rate between two assets according to the current rates.
"""
@inline function get_rate(
    er::ExchangeRates,
    from_idx::Int,
    to_idx::Int,
)
    _get_rate_idx(er, from_idx, to_idx)
end

@inline function get_rate(er::ExchangeRates, from::Cash, to::Cash)
    from_idx = from.index
    to_idx = to.index
    from_idx == to_idx && return 1.0
    rate = _get_rate_idx_or_nan(er, from_idx, to_idx)
    if isnan(rate)
        throw(ArgumentError("No exchange rate available from $(from.symbol) to $(to.symbol)."))
    end
    rate
end

"""
Builds an exchange rate matrix for all assets.

Rows represent the asset to convert from, columns the asset to convert to.
"""
function get_rates_matrix(er::ExchangeRates)
    n = length(er.rates)
    mat = fill(NaN, n, n)
    for f in 1:n
        for t in 1:n
            @inbounds mat[f, t] = _get_rate_idx_or_nan(er, f, t)
        end
    end
    mat
end

"""
Update the exchange rate between two assets.
"""
function update_rate!(er::ExchangeRates, from_idx::Int, to_idx::Int, rate::Real)
    isfinite(rate) && rate > 0 || throw(ArgumentError("Exchange rate must be a positive finite number."))
    r = Float64(rate)
    max_idx = max(from_idx, to_idx)
    max_idx > length(er.rates) && _ensure_rates_size!(er, max_idx)
    @inbounds er.rates[from_idx][to_idx] = r
    @inbounds er.rates[to_idx][from_idx] = 1.0 / r
    return nothing
end

@inline function update_rate!(er::ExchangeRates, from::Cash, to::Cash, rate::Real)
    update_rate!(er, from.index, to.index, rate)
end

function Base.show(io::IO, er::ExchangeRates)
    n = length(er.rates)
    n > 0 || return println(io, "No exchange rates available.")
    labels = string.(1:n)
    pretty_table(
        io,
        get_rates_matrix(er),
        ;
        column_labels=labels,
        row_labels=labels,
        compact_printing=true)
end
