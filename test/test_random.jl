module FastbackDummyTest

using Fastback
using Dates

# create instrument
inst = Instrument("AAPL");
# inst2 = Instrument("AAPL"; data=Dict(:a => 1))

# synthetic data
N = 100_000;
prices = 1000.0 .+ 100cumsum(randn(N) .+ 0.01);
bids = prices .- 0.01;
asks = prices .+ 0.01;
dts = map(x -> DateTime(2000, 1, 1) + Minute(x) + Millisecond(123), 1:N);

# create trading account
acc = Account(10_000.0);

# plot data collectors
collect_balance, balance_curve = periodic_collector(Float64, Second(1));
collect_equity, equity_curve = periodic_collector(Float64, Second(1));
collect_open_orders, open_orders_curve = max_value_collector(Int64);
collect_drawdown, drawdown_curve = drawdown_collector(Percentage::DrawdownMode, (v, dt, equity) -> dt - v.last_dt >= Second(1));

# backtest random trading strategy
for i in 1:N
    ba = BidAsk(dts[i], bids[i], asks[i])

    if i == N
        # # close all orders at end of backtest
        # for pos in acc.open_positions
        #     execute_order!(acc, CloseOrder(pos), ba)
        # end
        execute_order!(acc, OpenOrder(inst, 100.0, Long; data=i), ba)
    else
        # randomly trade
        if rand() > 0.99 && hour(ba.dt) < 15
            pos_dir = rand() > 0.5 ? Long::TradeDir : Short::TradeDir
            pos_size = match_target_exposure(acc.equity, pos_dir, ba)
            execute_order!(acc, OpenOrder(inst, pos_size, pos_dir; data=i), ba)
        end

        # close positions after 10 minutes
        for pos in acc.open_positions
            if ba.dt - pos.open_dt >= Minute(10)
                execute_order!(acc, CloseOrder(pos), ba)
            end
        end
    end

    update_account!(acc, inst, ba)

    # collect data for analysis
    collect_balance(ba.dt, acc.balance)
    collect_equity(ba.dt, acc.equity)
    collect_open_orders(ba.dt, length(acc.open_positions))
    collect_drawdown(ba.dt, acc.equity)
end

# print account
show(acc)

# print all closed positions as pretty table
print_positions(acc.closed_positions; max_print=NaN)

# print all closed position as pretty table including custom data column renderer
print_positions(acc.closed_positions; max_print=NaN, data_renderer=(pos, data) -> data)


# # plots
# include("../backtesting/plots.jl");
# using Measures
# gr();

# title_text = "Backtest $(inst.symbol)"
# title_plot = scatter(1:2,
#     marker=0,
#     markeralpha=0,
#     annotations=(1.5, 1.5, text(title_text)),
#     foreground_color_subplot=:white,
#     axis=false,
#     grid=false,
#     leg=false);
#
#
# # plot 1
# l = @layout[
#     a{0.04h} ;  # title
#     b ;         # equity
#     c{0.3h} ;   # drawdown
#     d{0.15h} ;  # open orders
# ];
# plot(
#     title_plot,
#     plot_equity(equity_curve),
#     plot_drawdown(drawdown_curve),
#     plot_open_orders(open_orders_curve),
#     titleloc = :left,
#     titlefont = font(10),
#     margin=0mm,
#     layout=l,
#     size=(750, 1000))
#
#
# # plot 2
# l = @layout[
#     a{0.04h} ;  # title
#     b ;         # returns dist. by day
#     c           # returns dist. by hour
# ];
# plot(
#     title_plot,
#     violin_nominal_returns_by_day(acc.closed_positions),
#     violin_nominal_returns_by_hour(acc.closed_positions);
#     titleloc = :left,
#     titlefont = font(10),
#     margin=0mm,
#     layout=l,
#     size=(750, 1000))
#
#
# # plot 3
# l = @layout[
#     a{0.04h} ;  # title
#     b ;         # cum. returns by day
#     c           # cum. returns by hour
# ];
# plot(
#     title_plot,
#     plot_nominal_cum_returns_by_hour(acc.closed_positions),
#     plot_nominal_cum_returns_by_weekday(acc.closed_positions);
#     titleloc = :left,
#     titlefont = font(10),
#     margin=0mm,
#     layout=l,
#     size=(750, 1000))

end # module
