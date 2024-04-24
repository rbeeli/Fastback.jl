module Fastback

const Price = Float64           # quote bid/ask, traded price
const Quantity = Float64        # trade volume / number of shares

include("utils.jl")
include("enums.jl")
include("instrument.jl")
include("order.jl")
include("execution.jl")
include("position.jl")
include("account.jl")
include("collectors.jl")
include("print.jl")
include("backtest_runner.jl")

# export all
for n in names(@__MODULE__; all=true)
    if Base.isidentifier(n) && n ∉ (Symbol(@__MODULE__), :eval, :include)
        @eval export $n
    end
end

end # module
