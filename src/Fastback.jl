module Fastback

include("utils.jl")
include("types.jl")
include("collectors.jl")
include("accessors.jl")
include("position.jl")
include("execution.jl")
include("account.jl")
include("print.jl")
include("backtest_runner.jl")

# # type aliases
# export Price, Volume, Return

# # enums
# export TradeDir, DrawdownMode

# # structs
# export Instrument, Position
# export Order, Execution, Transaction, Account
# export PeriodicValues, MinValue, MaxValue, DrawdownValues

# # account functions
# export fill_order!, adjust_position!, update_pnl!, has_position_with_inst, has_position_with_dir, equity_return, get_position

# # position functions
# export match_target_exposure, calc_pnl, calc_return, calc_realized_quantity, calc_exposure_increase_quantity

# # execution functions
# export calc_realized_pnl, calc_realized_price_return # calc_realized_return, 

# # backtest functions
# export batch_backtest

# # collection functions
# export should_collect, periodic_collector, predicate_collector, min_value_collector, max_value_collector, drawdown_collector

# # print helpers
# export print_positions, print_transactions

# # utils
# export params_combinations, estimate_eta, format_period_HHMMSS

# # accessors
# export is_long, is_short, trade_dir, pnl_net, pnl_gross, return_net, return_gross,
#     has_positions, total_return, opposite_dir
# #, total_pnl_net, total_pnl_gross, count_winners_net, count_winners_gross

# export all
for n in names(@__MODULE__; all=true)
    if Base.isidentifier(n) && n ∉ (Symbol(@__MODULE__), :eval, :include)
        @eval export $n
    end
end

end # module
