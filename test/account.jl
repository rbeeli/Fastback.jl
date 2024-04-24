using Fastback
using Test
using Dates

@testset "Account long order w/o fees" begin
    # create instrument
    DUMMY = Instrument(1, "DUMMY");
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
    quantity = 100
    order = Order(acc, DUMMY, dates[1], prices[1], quantity)
    exe1 = fill_order!(acc, order, dates[1], prices[1])

    @test exe1 == acc.executions[end]
    @test exe1.fees_ccy == 0
    @test nominal_value(exe1) == quantity * prices[1]
    @test realized_pnl(exe1) == 0.0
    # @test realized_return(exe1) == 0.0
    @test pos.avg_price == 100.0

    # update position and account P&L
    update_pnl!(acc, pos, prices[2])

    @test pos.pnl ≈ (prices[2] - prices[1]) * pos.quantity
    @test acc.balance ≈ 100_000.0 - pos.quantity * prices[1]
    @test acc.equity ≈ acc.initial_balance + (prices[2] - prices[1]) * pos.quantity

    # close position
    order = Order(acc, DUMMY, dates[3], prices[3], -pos.quantity)
    fill_order!(acc, order, dates[3], prices[3])

    # update position and account P&L
    update_pnl!(acc, pos, prices[3])

    @test pos.pnl ≈ 0
    @test acc.balance ≈ 100_000.0 + (prices[3] - prices[1]) * quantity
    @test acc.equity ≈ acc.balance

    show(acc)
end

@testset "Account long order w/ fees ccy" begin
    # create instrument
    DUMMY = Instrument(1, "DUMMY");
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
    quantity = 100
    order = Order(acc, DUMMY, dates[1], prices[1], quantity)
    fees_ccy = 1
    exe1 = fill_order!(acc, order, dates[1], prices[1]; fees_ccy=fees_ccy)

    @test exe1 == acc.executions[end]
    @test nominal_value(exe1) == quantity * prices[1]
    @test exe1.fees_ccy == fees_ccy
    @test realized_pnl(exe1) == -fees_ccy
    # @test realized_return(exe1) == 0.0
    @test pos.avg_price == 100.0

    # update position and account P&L
    update_pnl!(acc, pos, prices[2])

    @test pos.pnl ≈ (prices[2] - prices[1]) * pos.quantity # does not include fees!
    @test acc.balance ≈ 100_000.0 - pos.quantity * prices[1] - fees_ccy
    @test acc.equity ≈ acc.initial_balance + (prices[2] - prices[1]) * pos.quantity - fees_ccy

    # close position
    order = Order(acc, DUMMY, dates[3], prices[3], -pos.quantity)
    exe2 = fill_order!(acc, order, dates[3], prices[3]; fees_ccy=0.5)

    # update position and account P&L
    update_pnl!(acc, pos, prices[3])

    @test pos.pnl ≈ 0
    @test acc.balance ≈ 100_000.0 + (prices[3] - prices[1]) * quantity - fees_ccy - 0.5
    @test acc.equity ≈ acc.balance

    show(acc)
end

@testset "Account long order w/ fees pct" begin
    # create instrument
    DUMMY = Instrument(1, "DUMMY");
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
    quantity = 100
    order = Order(acc, DUMMY, dates[1], prices[1], quantity)
    fees_pct1 = 0.001
    exe1 = fill_order!(acc, order, dates[1], prices[1]; fees_pct=fees_pct1)

    @test nominal_value(exe1) == quantity * prices[1]
    @test exe1.fees_ccy == fees_pct1*nominal_value(exe1)
    @test realized_pnl(acc.executions[end]) == -fees_pct1*nominal_value(exe1)
    # @test realized_return(acc.executions[end]) == 0.0
    @test pos.avg_price == 100.0

    # update position and account P&L
    update_pnl!(acc, pos, prices[2])

    @test pos.pnl ≈ (prices[2] - prices[1]) * pos.quantity # does not include fees
    @test acc.balance ≈ 100_000.0 - nominal_value(exe1) - exe1.fees_ccy
    @test acc.equity ≈ acc.initial_balance + (prices[2] - prices[1]) * pos.quantity - exe1.fees_ccy

    # close position
    order = Order(acc, DUMMY, dates[3], prices[3], -pos.quantity)
    exe2 = fill_order!(acc, order, dates[3], prices[3]; fees_pct=0.0005)

    # update position and account P&L
    update_pnl!(acc, pos, prices[3])

    @test pos.pnl ≈ 0
    @test acc.balance ≈ 100_000.0 + (prices[3] - prices[1]) * quantity - exe1.fees_ccy - exe2.fees_ccy
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
#     @test acc.balance ≈ 100_000.0 - pos.quantity * prices[1].bid
#     @test acc.equity ≈ 99_900.0

#     update_book!(book, prices[2])
#     update_account!(acc, data, inst)

#     @test pos.pnl ≈ -200
#     @test acc.balance ≈ 100_000.0 - pos.quantity * prices[1].bid
#     @test acc.equity ≈ 99_800.0

#     update_book!(book, prices[3])
#     update_account!(acc, data, inst)

#     # open long order (results in net long +100)
#     execute_order!(acc, book, Order(inst, 200.0, prices[3].dt))

#     @test acc.positions[inst.index].avg_price == book.bba.ask
#     @test realized_return(acc.executions[end].execution) ≈ (100.0 - 103.0) / 100.0
#     @test realized_pnl(acc.executions[end].execution) ≈ -300.0
#     # @test calc_realized_return(acc.executions[end].execution) ≈ (100.0 - 103.0) / 100.0
#     @test acc.executions[end].execution.realized_pnl ≈ -300.0
#     @test pos.pnl ≈ -50
#     @test acc.balance ≈ 100_000.0 + sum(t.execution.realized_pnl for t in acc.executions) - pos.quantity * prices[3].ask
#     @test acc.equity ≈ 99_650.0

#     update_book!(book, prices[4])
#     update_account!(acc, data, inst)

#     @test acc.equity ≈ 99_400.0

#     # open short order (results in net short -50)
#     execute_order!(acc, book, Order(inst, -150.0, prices[4].dt))

#     @test acc.positions[inst.index].avg_price == book.bba.bid
#     @test acc.executions[end].execution.realized_pnl ≈ -300.0
#     @test pos.pnl ≈ -25
#     @test acc.balance ≈ 100_000.0 + sum(t.execution.realized_pnl for t in acc.executions) - pos.quantity * prices[4].bid
#     @test acc.equity ≈ 99_375.0

#     # close open position
#     execute_order!(acc, book, Order(inst, 50.0, prices[4].dt))

#     @test acc.balance ≈ 99_375.0
#     @test acc.equity ≈ 99_375.0
#     @test acc.executions[end].execution.realized_pnl ≈ -25.0

#     @test pos.quantity == 0.0
#     @test pos.avg_price == 0.0
#     @test pos.pnl == 0.0
#     @test length(pos.executions) == 4

#     @test acc.equity == acc.initial_balance + sum(t.execution.realized_pnl for t in acc.executions)
#     @test acc.balance == acc.equity

#     # realized_orders = filter(t -> t.execution.realized_pnl != 0.0, acc.executions)
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
