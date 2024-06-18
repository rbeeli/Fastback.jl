using Random
using Dates
using Printf

"""
    params_combinations(params; filter, shuffle)

Creates a list of Dict with all possible combinates of the provided
parameters. Each element of the list represents a parameter-set.
Optionally, a filter function can be supplied for invalid and/or
unwanted parameter-sets.

# Arguments
- `params`:  Dict where each key holds a list with all possible values.
- `filter`:  Optional function for filtering parameter-sets. Return false
             to omit a given parameter-set.
             Example: `filter=x -> x[:key1] > 0.5 || x[:key2] < 1.0`
- `shuffle`: Randomly shuffles returned combinations if set to true.

# Returns
List of Dict with (filtered) parameter-sets.

# Examples
```jldoctest
julia> params_combinations(Dict("wnd" => [1,2,3], :mode => ["A"], "coef" => [0.1, 0.5, 1.0]))
9-element Array{Dict{Any,Any},1}:
    Dict("wnd" => 1,:mode => "A","coef" => 0.1)
    Dict("wnd" => 1,:mode => "A","coef" => 0.5)
    Dict("wnd" => 1,:mode => "A","coef" => 1.0)
    Dict("wnd" => 2,:mode => "A","coef" => 0.1)
    Dict("wnd" => 2,:mode => "A","coef" => 0.5)
    Dict("wnd" => 2,:mode => "A","coef" => 1.0)
    Dict("wnd" => 3,:mode => "A","coef" => 0.1)
    Dict("wnd" => 3,:mode => "A","coef" => 0.5)
    Dict("wnd" => 3,:mode => "A","coef" => 1.0)
julia>
julia> params = Dict(:wnd => [1,2], :mode => ["A", "B"], :coef => [0.1, 0.5]);
julia> filter = x -> x[:mode] != "A" || x[:wnd] > 1;
julia> params_combinations(params; filter=filter)
6-element Array{Dict{Any,Any},1}:
    Dict(:mode => "A",:wnd => 2,:coef => 0.1)
    Dict(:mode => "A",:wnd => 2,:coef => 0.5)
    Dict(:mode => "B",:wnd => 1,:coef => 0.1)
    Dict(:mode => "B",:wnd => 1,:coef => 0.5)
    Dict(:mode => "B",:wnd => 2,:coef => 0.1)
    Dict(:mode => "B",:wnd => 2,:coef => 0.5)
```
"""
function params_combinations(
    params;      # ::Dict{Any, Vector{Any}};
    filter::TF=x -> true,
    shuffle=false
) where {TF<:Function}
    # recursive implementation
    result = Vector{Dict{keytype(params),eltype(valtype(params))}}()
    tmp_keys = collect(keys(params))
    tmp_values = Vector{eltype(valtype(params))}(undef, length(params))
    params_combinations_internal(params, filter, result, 1, tmp_keys, tmp_values)
    shuffle && shuffle!(result)
    result
end

function params_combinations_internal(
    params,
    filter::TF,
    result,
    key_pos,
    tmp_keys,
    tmp_values
) where {TF<:Function}
    if key_pos <= length(params)
        key_params = params[tmp_keys[key_pos]]
        for param in key_params
            # set param value for this iteration
            tmp_values[key_pos] = param

            # call recursively for next set of values of one parameter
            params_combinations_internal(params, filter, result, key_pos + 1, tmp_keys, tmp_values)
        end
    else
        # parameter-set finished, add to result set
        new_parameterset = Dict{keytype(params),eltype(valtype(params))}(zip(tmp_keys, tmp_values))

        # check filter function
        if filter(new_parameterset)
            push!(result, new_parameterset)
        end
    end
    return # if-block returns a value otherwise
end


"""
    compute_eta(elapsed:, frac_processed)

Calculate the Estimated Time of Arrival (ETA) given the elapsed time and the fraction of the task that has been processed.

# Arguments
- `elapsed`:
A Period object representing the time that has already elapsed.
This could be in any time unit such as seconds, minutes, hours, etc.

- `frac_processed`:
A Float64 representing the fraction of the task that has been processed (between 0 and 1 inclusive).
If this value is 0, the function returns "Inf" indicating that the task has not yet begun.

# Returns
- Calculated ETA value as Period object. Returns NaN if frac_processed is 0.
"""
function compute_eta(elapsed, frac_processed)
    # check if fraction_processed is zero to avoid division by zero
    if frac_processed == 0
        return NaN
    end
    elapsed_ms = convert(Dates.Millisecond, elapsed)
    eta_ms = Millisecond(ceil(Int, (1 - frac_processed) * Dates.value(elapsed_ms) / frac_processed))
    eta_ms
end


"""
    format_period_HHMMSS(period; nan_value="Inf")

Formats a Period object into a string in the format HH:MM:SS. 

# Arguments
- `period`: A Period object. This could be in any time unit such as seconds, minutes, hours, etc.
- `nan_value`: An optional string to be returned if the input is a NaN value. The default is "Inf".

# Returns
- A string representing the input period in HH:MM:SS format. If the input is NaN, returns the value specified by `nan_value`.

# Examples
```julia
format_period_HHMMSS(Dates.Hour(1) + Dates.Minute(30) + Dates.Second(45))  # returns "01:30:45"
format_period_HHMMSS(NaN)  # returns "Inf"
format_period_HHMMSS(NaN, nan_value="N/A")  # returns "N/A"
```
"""
function format_period_HHMMSS(period; nan_value="Inf")
    if isa(period, Real) && isnan(period)
        return nan_value
    end
    period = convert(Millisecond, period)
    hours = Dates.value(floor(period, Hour))
    minutes = Dates.value(floor(period, Minute)) % 60
    seconds = Dates.value(floor(period, Second)) % 60
    @sprintf("%02d:%02d:%02d", hours, minutes, seconds)
end




# using BenchmarkTools

# const prices1 = collect(1.0:0.00001:100.0);

# @benchmark log_returns(prices1) samples=30


# function downsample(dts::Vector{DateTime}, additive_rets::Vector{Return})
#     zipped = zip(dts, additive_rets)
#     sampled = zipped |>
#         @groupby(Dates.Date(_[1])) |>
#         @orderby(key(_)) |>
#         @map(key(_) => sum(map(x -> x[2], _))) |>
#         collect
#     map(x -> x[1], sampled), map(x -> x[2], sampled)
# end
