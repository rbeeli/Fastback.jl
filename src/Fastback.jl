module Fastback

include("types.jl")
include("accessors.jl")
include("collectors.jl")
include("position_functions.jl")
include("account_functions.jl")
include("backtest_runner.jl")
include("print.jl")
include("utils.jl")

# structs
export Instrument
export BidAsk
export Position
export Order
export OpenOrder
export CloseOrder
export CloseAllOrder
export Account
export PeriodicValues
export MinValue
export MaxValue
export DrawdownValues

# enums
export CloseReason, NullReason, StopLoss, TakeProfit
export TradeDir, NullDir, Long, Short
export DrawdownMode, Percentage, PnL
# export TradeMode, LongShort::TradeMode, LongOnly::TradeMode, ShortOnly::TradeMode

# type aliases
export Price, Volume, Return

# account functions
export execute_order!, book_position!, update_pnl!, update_account!, close_position!

# position functions
export match_target_exposure

# backtest functions
export batch_backtest

# collection functions
export should_collect, periodic_collector, predicate_collector, min_value_collector, max_value_collector, drawdown_collector

# print helpers
export print_positions

# utils
export params_combinations, estimate_eta, format_period_HHMMSS

# accessors
export midprice, spread, open_price, close_price, is_long, is_short, pnl_net, pnl_gross, return_net, return_gross,
    balance_ret, equity_ret, has_open_positions, has_closed_positions, total_return, total_pnl_net, total_pnl_gross, 
    count_winners_net, count_winners_gross, has_open_position_with_dir, opposite_dir

end # module
