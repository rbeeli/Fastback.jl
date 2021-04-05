import Random


"""
    permute_params(params; filter)

Creates a list of dictionaries with all possible combinates of the provided
parameters `params`, where each element in `params` represents one parameter and
all its possible values. Optionally, a validator function can be supplied
to filter invalid or unwanted parameter combinations.

# Arguments
- `params`:  Dictionary where each element holds a list with all possible values.
- `filter`:  Function for filtering parameter combinations. It is called with one argument of type `Dict{Any, Any}` and expects a `Bool` return value.
             Example: `filter=x -> x[:key1] > 0.5 || x[:key2] < 1.0`
- `shuffle`: Indicates whether to randomly shuffle combinations.

# Returns
List of dictionaries with all possible parameter combinations.

# Examples
```jldoctest
julia> permute_params(Dict{Any, Vector{Any}}("wnd" => [1,2,3], :mode => ["A"], "coef" => [0.1, 0.5, 1.0]))

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
julia> params = Dict{Any, Vector{Any}}(:wnd => [1,2], :mode => ["A", "B"], :coef => [0.1, 0.5]);
julia> filter = x -> x[:mode] != "A" || x[:wnd] > 1;
julia> permute_params(params; filter=filter)
6-element Array{Dict{Any,Any},1}:
    Dict(:mode => "A",:wnd => 2,:coef => 0.1)
    Dict(:mode => "A",:wnd => 2,:coef => 0.5)
    Dict(:mode => "B",:wnd => 1,:coef => 0.1)
    Dict(:mode => "B",:wnd => 1,:coef => 0.5)
    Dict(:mode => "B",:wnd => 2,:coef => 0.1)
    Dict(:mode => "B",:wnd => 2,:coef => 0.5)
```
"""
function permute_params(params::Dict{Any, Vector{Any}}; filter::Function=x -> true, shuffle::Bool=false)::Vector{Dict{Any, Any}}
    result = Vector{Dict{Any, Any}}()
    permute_params_internal(params, Dict{Any, Any}(), filter, result)
    if shuffle
        Random.shuffle!(result)
    end
    result
end


function permute_params_internal(
    params          ::Dict{Any, Vector{Any}},
    fixed_params    ::Dict{Any, Any},
    filter          ::Function,
    result          ::Vector{Dict{Any, Any}}
)::Nothing
    if !isempty(params)
        params2 = copy(params)
        key = collect(keys(params))[1]
        all_key_values = params2[key]
        delete!(params2, key)
        for val in all_key_values
            fixed_params2 = copy(fixed_params)
            fixed_params2[key] = val
            permute_params_internal(params2, fixed_params2, filter, result)
        end
    else
        if filter(fixed_params)
            push!(result, fixed_params)
        end
    end
    nothing
end
