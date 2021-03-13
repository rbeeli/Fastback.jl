"""
    permute_params(params)

Creates a list of dictionaries with all possible parameter
combinates as provided by `params`, where each element in `params`
holds a list of all possible values for that parameter.

Input:

        `params`    Dictionary where each element holds a list of possible values.

Returns:

        Dictionary with all possible combinations of the passed parameters.

Example:

        ```
        permute_params(Dict{Any, Vector{Any}}("wnd" => [1,2,3], :mode => ["A", "B"], "coef" => [0.1, 0.5, 1.0]))
        ```
"""
function permute_params(params::Dict{Any, Vector{Any}})::Vector{Dict{Any, Any}}
    result = Vector{Dict{Any, Any}}()
    permute_params_internal(params, Dict{Any, Any}(), result)
    return result
end


function permute_params_internal(
    params::Dict{Any, Vector{Any}},
    fixed_params::Dict{Any, Any},
    result::Vector{Dict{Any, Any}})

    if !isempty(params)
        params2 = copy(params)
        key = collect(keys(params))[1]
        all_key_values = params2[key]
        delete!(params2, key)
        for val in all_key_values
            fixed_params2 = copy(fixed_params)
            fixed_params2[key] = val
            permute_params_internal(params2, fixed_params2, result)
        end
    else
        push!(result, fixed_params)
    end
end
