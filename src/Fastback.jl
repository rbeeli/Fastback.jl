module Fastback

include("types.jl")
include("accessors.jl")
include("collectors.jl")
include("permute.jl")
include("position_functions.jl")
include("account_functions.jl")
include("backtest_runner.jl")
include("print.jl")
include("utils.jl")
include("statistics.jl")

# export all
for n in names(@__MODULE__; all=true)
   if Base.isidentifier(n) && n ∉ (Symbol(@__MODULE__), :eval, :include)
       @eval export $n
   end
end

# # structs
# export Instrument
# export BidAsk
# export Position
# export Account
# export PeriodicValues
# export Order
# export OpenOrder
# export CloseOrder
# export CloseAllOrder
#
# # enums
# export CloseReason, Unspecified, StopLoss, TakeProfit
# export TradeDir, Undefined, Long, Short
# export TradeMode, LongShort, LongOnly, ShortOnly
#
# # type aliases
# export Price, Volume
#
# # account functions
# export execute_order!, update_pnl!, update_account!
#
# # collection functions
# export value_collector, drawdown_collector, max_value_collector

end # module
