using Fastback
using Test
using Dates

@testset "Account long order w/o fees" begin
    # create instrument
    DUMMY = Instrument(1, Symbol("DUMMY"));
    instruments = [DUMMY];

    # create trading account
    acc = Account{Nothing}(instruments, 100_000.0)

    @test acc.initial_balance == 100_000.0
    @test acc.balance == 100_000.0
    @test acc.equity == 100_000.0

    pos = get_position(acc, DUMMY)

    # generate data
    dates = collect(DateTime(2018, 1, 2):Day(1):DateTime(2018, 1, 4))
    prices = [100.0, 100.5, 102.5]

    # buy order
    qty = 100.0
    order = Order(oid!(acc), DUMMY, dates[1], prices[1], qty)
    exe1 = fill_order!(acc, order, dates[1], prices[1])

    @test exe1 == acc.trades[end]
    @test exe1.fee_ccy == 0.0
    @test nominal_value(exe1) == qty * prices[1]
    @test realized_pnl(exe1) == 0.0
    # @test realized_return(exe1) == 0.0
    @test pos.avg_price == 100.0

    # update position and account P&L
    update_pnl!(acc, pos, prices[2])

    @test pnl(pos) ≈ (prices[2] - prices[1]) * quantity(pos)
    @test balance(acc) ≈ 100_000.0
    @test equity(acc) ≈ initial_balance(acc) + (prices[2] - prices[1]) * quantity(pos)

    # close position
    order = Order(oid!(acc), DUMMY, dates[3], prices[3], -quantity(pos))
    fill_order!(acc, order, dates[3], prices[3])

    # update position and account P&L
    update_pnl!(acc, pos, prices[3])

    @test pnl(pos) ≈ 0
    @test balance(acc) ≈ 100_000.0 + (prices[3] - prices[1]) * qty
    @test equity(acc) ≈ balance(acc)

    show(acc)
end

@testset "Account long order w/ fees ccy" begin
    # create instrument
    DUMMY = Instrument(1, Symbol("DUMMY"));
    instruments = [DUMMY];

    # create trading account
    acc = Account{Nothing}(instruments, 100_000.0)

    @test acc.initial_balance == 100_000.0
    @test acc.balance == 100_000.0
    @test acc.equity == 100_000.0

    pos = get_position(acc, DUMMY)

    # generate data
    dates = collect(DateTime(2018, 1, 2):Day(1):DateTime(2018, 1, 4))
    prices = [100.0, 100.5, 102.5]

    # buy order
    qty = 100.0
    order = Order(oid!(acc), DUMMY, dates[1], prices[1], qty)
    fee_ccy = 1.0
    exe1 = fill_order!(acc, order, dates[1], prices[1]; fee_ccy=fee_ccy)

    @test exe1 == acc.trades[end]
    @test nominal_value(exe1) == qty * prices[1]
    @test exe1.fee_ccy == fee_ccy
    @test realized_pnl(exe1) == -fee_ccy
    # @test realized_return(exe1) == 0.0
    @test pos.avg_price == 100.0

    # update position and account P&L
    update_pnl!(acc, pos, prices[2])

    @test pos.pnl ≈ (prices[2] - prices[1]) * quantity(pos) # does not include fees!
    @test acc.balance ≈ 100_000.0 - fee_ccy
    @test acc.equity ≈ acc.initial_balance + (prices[2] - prices[1]) * quantity(pos) - fee_ccy

    # close position
    order = Order(oid!(acc), DUMMY, dates[3], prices[3], -quantity(pos))
    exe2 = fill_order!(acc, order, dates[3], prices[3]; fee_ccy=0.5)

    # update position and account P&L
    update_pnl!(acc, pos, prices[3])

    @test pos.pnl ≈ 0
    @test acc.balance ≈ 100_000.0 + (prices[3] - prices[1]) * qty - fee_ccy - 0.5
    @test acc.equity ≈ acc.balance

    show(acc)
end

@testset "Account long order w/ fees pct" begin
    # create instrument
    DUMMY = Instrument(1, Symbol("DUMMY"));
    instruments = [DUMMY];

    # create trading account
    acc = Account{Nothing}(instruments, 100_000.0)

    @test acc.initial_balance == 100_000.0
    @test acc.balance == 100_000.0
    @test acc.equity == 100_000.0

    pos = get_position(acc, DUMMY)

    # generate data
    dates = collect(DateTime(2018, 1, 2):Day(1):DateTime(2018, 1, 4))
    prices = [100.0, 100.5, 102.5]

    # buy order
    qty = 100.0
    order = Order(oid!(acc), DUMMY, dates[1], prices[1], qty)
    fee_pct1 = 0.001
    exe1 = fill_order!(acc, order, dates[1], prices[1]; fee_pct=fee_pct1)

    @test nominal_value(exe1) == qty * prices[1]
    @test exe1.fee_ccy == fee_pct1*nominal_value(exe1)
    @test realized_pnl(acc.trades[end]) == -fee_pct1*nominal_value(exe1)
    # @test realized_return(acc.trades[end]) == 0.0
    @test pos.avg_price == 100.0

    # update position and account P&L
    update_pnl!(acc, pos, prices[2])

    @test pos.pnl ≈ (prices[2] - prices[1]) * quantity(pos) # does not include fees
    @test acc.balance ≈ 100_000.0 - exe1.fee_ccy
    @test acc.equity ≈ acc.initial_balance + (prices[2] - prices[1]) * quantity(pos) - exe1.fee_ccy

    # close position
    order = Order(oid!(acc), DUMMY, dates[3], prices[3], -quantity(pos))
    exe2 = fill_order!(acc, order, dates[3], prices[3]; fee_pct=0.0005)

    # update position and account P&L
    update_pnl!(acc, pos, prices[3])

    @test pos.pnl ≈ 0
    @test acc.balance ≈ 100_000.0 + (prices[3] - prices[1]) * qty - exe1.fee_ccy - exe2.fee_ccy
    @test acc.equity ≈ acc.balance

    show(acc)
end


# @testset "Backtesting single ticker net long/short swap" begin
#     # create instrument
#     inst = Instrument(1, "TICKER")
#     insts = [inst]

#     # market data (order books)
#     data = MarketData(insts)

#     # order book for instrument
#     book = data.order_books[inst.index]

#     # create trading account
#     acc = Account(insts, 100_000.0)

#     # generate data
#     prices = [
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 0), 100.0, 101.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 1), 100.5, 102.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 2), 102.5, 103.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 3), 100.0, 100.5),
#     ]

#     pos = acc.positions[inst.index]

#     update_book!(book, prices[1])

#     execute_order!(acc, book, Order(inst, -100.0, prices[1].dt))
#     @test acc.positions[inst.index].avg_price == book.bba.bid

#     update_account!(acc, data, inst)

#     @test pos.pnl ≈ -100
#     @test acc.balance ≈ 100_000.0 - quantity(pos) * prices[1].bid
#     @test acc.equity ≈ 99_900.0

#     update_book!(book, prices[2])
#     update_account!(acc, data, inst)

#     @test pos.pnl ≈ -200
#     @test acc.balance ≈ 100_000.0 - quantity(pos) * prices[1].bid
#     @test acc.equity ≈ 99_800.0

#     update_book!(book, prices[3])
#     update_account!(acc, data, inst)

#     # open long order (results in net long +100)
#     execute_order!(acc, book, Order(inst, 200.0, prices[3].dt))

#     @test acc.positions[inst.index].avg_price == book.bba.ask
#     @test realized_return(acc.trades[end].execution) ≈ (100.0 - 103.0) / 100.0
#     @test realized_pnl(acc.trades[end].execution) ≈ -300.0
#     # @test calc_realized_return(acc.trades[end].execution) ≈ (100.0 - 103.0) / 100.0
#     @test acc.trades[end].execution.realized_pnl ≈ -300.0
#     @test pos.pnl ≈ -50
#     @test acc.balance ≈ 100_000.0 + sum(t.execution.realized_pnl for t in acc.trades) - quantity(pos) * prices[3].ask
#     @test acc.equity ≈ 99_650.0

#     update_book!(book, prices[4])
#     update_account!(acc, data, inst)

#     @test acc.equity ≈ 99_400.0

#     # open short order (results in net short -50)
#     execute_order!(acc, book, Order(inst, -150.0, prices[4].dt))

#     @test acc.positions[inst.index].avg_price == book.bba.bid
#     @test acc.trades[end].execution.realized_pnl ≈ -300.0
#     @test pos.pnl ≈ -25
#     @test acc.balance ≈ 100_000.0 + sum(t.execution.realized_pnl for t in acc.trades) - quantity(pos) * prices[4].bid
#     @test acc.equity ≈ 99_375.0

#     # close open position
#     execute_order!(acc, book, Order(inst, 50.0, prices[4].dt))

#     @test acc.balance ≈ 99_375.0
#     @test acc.equity ≈ 99_375.0
#     @test acc.trades[end].execution.realized_pnl ≈ -25.0

#     @test quantity(pos) == 0.0
#     @test pos.avg_price == 0.0
#     @test pos.pnl == 0.0
#     @test length(pos.trades) == 4

#     @test acc.equity == acc.initial_balance + sum(t.execution.realized_pnl for t in acc.trades)
#     @test acc.balance == acc.equity

#     # realized_orders = filter(t -> t.execution.realized_pnl != 0.0, acc.trades)
#     # @test equity_return(acc) ≈ sum(calc_realized_return(o)*o.execution.weight for o in realized_orders)
# end


# @testset "Backtesting single ticker avg_price" begin
#     # create instrument
#     inst = Instrument(1, "TICKER")
#     insts = [inst]

#     # market data (order books)
#     data = MarketData(insts)

#     # order book for instrument
#     book = data.order_books[inst.index]

#     # create trading account
#     acc = Account(insts, 100_000.0)

#     # generate data
#     prices = [
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 0), 100.0, 101.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 1), 100.5, 102.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 2), 102.5, 103.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 3), 100.0, 100.5),
#     ]

#     pos = acc.positions[inst.index]

#     update_book!(book, prices[1])
#     update_account!(acc, data, inst)

#     # buy order (net long +100)
#     execute_order!(acc, book, Order(inst, 100.0, prices[1].dt))
#     @test acc.positions[inst.index].avg_price == prices[1].ask

#     update_book!(book, prices[2])
#     update_account!(acc, data, inst)

#     # sell order (reduce exposure to net long +50)
#     execute_order!(acc, book, Order(inst, -50.0, prices[2].dt))
#     @test acc.positions[inst.index].avg_price == prices[1].ask

#     update_book!(book, prices[3])
#     update_account!(acc, data, inst)

#     # flip exposure (net short -50)
#     execute_order!(acc, book, Order(inst, -100.0, prices[3].dt))
#     @test acc.positions[inst.index].avg_price == prices[3].bid

#     update_book!(book, prices[4])
#     update_account!(acc, data, inst)

#     # close all positions
#     execute_order!(acc, book, Order(inst, 50.0, prices[4].dt))
#     @test acc.positions[inst.index].avg_price == 0.0
# end
