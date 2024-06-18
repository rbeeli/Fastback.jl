module Fastback

const Price = Float64           # quote bid/ask, traded price
const Quantity = Float64        # trade volume / number of shares

include("utils.jl")
include("enums.jl")
include("cash.jl")
include("instrument.jl")
include("order.jl")
include("trade.jl")
include("position.jl")
include("exchange_rates.jl")
include("account.jl")
include("logic.jl")
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
