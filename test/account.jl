using Fastback
using Test
using Dates


@testset "Backtesting single ticker" begin

    # create instrument
    inst = Instrument(1, "TICKER")
    insts = [inst]

    # market data (order books)
    data = MarketData(insts)

    # order book for instrument
    book = data.order_books[inst.index]

    # create trading account
    acc = Account(insts, 100_000.0)

    # generate data
    dt = DateTime(2018, 1, 2, 9, 30, 0)
    prices = [
        BidAsk(dt + Second(1), 100.0, 101.0),
        BidAsk(dt + Second(2), 100.5, 102.0),
        BidAsk(dt + Second(3), 102.5, 103.0)
    ]

    @test acc.initial_balance == 100_000.0
    @test acc.balance == 100_000.0
    @test acc.equity == 100_000.0

    # update order book
    update_book!(book, prices[1])

    # open long order
    execute_order!(acc, book, Order(inst, 100.0, prices[1].dt))

    # update account
    update_account!(acc, data, inst)

    @test acc.positions[inst.index].pnl ≈ -100
    @test acc.balance ≈ 100_000.0 - acc.positions[inst.index].quantity * prices[1].ask
    @test acc.equity ≈ 99_900.0

    # update order book
    update_book!(book, prices[2])

    # update account
    update_account!(acc, data, inst)

    @test acc.positions[inst.index].pnl ≈ -50
    @test acc.balance ≈ 100_000.0 - acc.positions[inst.index].quantity * prices[1].ask
    @test acc.equity ≈ 99_950.0

    # update order book
    update_book!(book, prices[3])

    # update account
    update_account!(acc, data, inst)

    # close order again
    execute_order!(acc, book, Order(inst, -100.0, prices[3].dt))

    @test acc.positions[inst.index].orders_history[end].execution.realized_pnl ≈ 150

    @test acc.positions[inst.index].quantity == 0.0
    @test acc.positions[inst.index].avg_price == 0.0
    @test acc.positions[inst.index].pnl == 0.0
    @test length(acc.positions[inst.index].orders_history) == 2

    @test acc.balance ≈ 100_150.0
    @test acc.equity ≈ 100_150.0

    @test acc.equity == acc.initial_balance + sum(order.execution.realized_pnl for order in acc.orders_history)
    @test acc.balance == acc.equity

end

@testset "Single ticker + collectors" begin

    inst = Instrument(1, "TICKER")
    insts = [inst]

    # generate data
    data = Dict{Instrument,Vector{BidAsk}}()
    dt = DateTime(2018, 1, 2, 9, 30, 0)
    data[inst] = [
        BidAsk(dt + Second(1), 100.0, 101.0),
        BidAsk(dt + Second(2), 100.5, 102.0),
        BidAsk(dt + Second(3), 102.5, 103.0),
        BidAsk(dt + Second(4), 101.0, 102.0),
        BidAsk(dt + Second(5), 99.5, 100.0),
        BidAsk(dt + Second(6), 101.5, 102.0),
        BidAsk(dt + Second(7), 103.5, 104.0),
        BidAsk(dt + Second(8), 104.5, 105.0)
    ]

    # market data (order books)
    market_data = MarketData(insts)

    # create trading account
    acc = Account(insts, 10_000.0)
    collect_balance, balance_curve = periodic_collector(Float64, Second(1))
    collect_equity, equity_curve = periodic_collector(Float64, Second(1))

    book = OrderBook(1, inst, data[inst][1])

    # dummy backtest
    for (i, ba) in enumerate(data[inst])
        update_book!(book, ba)
        update_account!(acc, market_data, inst)

        if i == 1
            execute_order!(acc, book, Order(inst, 500.0, ba.dt))
        end

        if i == 7
            execute_order!(acc, book, Order(inst, -acc.positions[inst.index].quantity, ba.dt))
        end

        # collect data for analysis
        collect_balance(ba.dt, acc.balance)
        collect_equity(ba.dt, acc.equity)
    end

    @test length(balance_curve.values) == 8
    @test length(equity_curve.values) == 8
    @test equity_curve.values[end][2] == acc.equity
    @test balance_curve.values[end][2] == acc.balance

    @test length(acc.orders_history) == 2
    @test acc.orders_history[1].execution.quantity == 500.0

end


@testset "Backtesting single ticker net long/short swap" begin

    # create instrument
    inst = Instrument(1, "TICKER")
    insts = [inst]

    # market data (order books)
    data = MarketData(insts)

    # order book for instrument
    book = data.order_books[inst.index]

    # create trading account
    acc = Account(insts, 100_000.0)

    # generate data
    dt = DateTime(2018, 1, 2, 9, 30, 0)
    prices = [
        BidAsk(dt + Second(1), 100.0, 101.0),
        BidAsk(dt + Second(2), 100.5, 102.0),
        BidAsk(dt + Second(3), 102.5, 103.0),
        BidAsk(dt + Second(4), 100.0, 100.5)
    ]

    pos = acc.positions[inst.index]

    # update order book
    update_book!(book, prices[1])

    # open short order
    execute_order!(acc, book, Order(inst, -100.0, prices[1].dt))

    # update account
    update_account!(acc, data, inst)

    @test pos.pnl ≈ -100
    @test acc.balance ≈ 100_000.0 - pos.quantity * prices[1].bid
    @test acc.equity ≈ 99_900.0

    # update order book
    update_book!(book, prices[2])

    # update account
    update_account!(acc, data, inst)

    @test pos.pnl ≈ -200
    @test acc.balance ≈ 100_000.0 - pos.quantity * prices[1].bid
    @test acc.equity ≈ 99_800.0

    # update order book
    update_book!(book, prices[3])

    # update account
    update_account!(acc, data, inst)

    # open long order (results in net long +100)
    execute_order!(acc, book, Order(inst, 200.0, prices[3].dt))

    @test acc.orders_history[end].execution.realized_pnl ≈ -300.0
    @test pos.pnl ≈ -50
    @test acc.balance ≈ 100_000.0 + sum(o.execution.realized_pnl for o in acc.orders_history) - pos.quantity * prices[3].ask
    @test acc.equity ≈ 99_650.0

    # update order book
    update_book!(book, prices[4])

    # update account
    update_account!(acc, data, inst)

    @test acc.equity ≈ 99_400.0

    # open short order (results in net short -50)
    execute_order!(acc, book, Order(inst, -150.0, prices[4].dt))

    @test acc.orders_history[end].execution.realized_pnl ≈ -300.0
    @test pos.pnl ≈ -25
    @test acc.balance ≈ 100_000.0 + sum(o.execution.realized_pnl for o in acc.orders_history) - pos.quantity * prices[4].bid
    @test acc.equity ≈ 99_375.0

    # close open position
    execute_order!(acc, book, Order(inst, 50.0, prices[4].dt))

    @test acc.balance ≈ 99_375.0
    @test acc.equity ≈ 99_375.0
    @test acc.orders_history[end].execution.realized_pnl ≈ -25.0

    @test pos.quantity == 0.0
    @test pos.avg_price == 0.0
    @test pos.pnl == 0.0
    @test length(pos.orders_history) == 4

    @test acc.equity == acc.initial_balance + sum(order.execution.realized_pnl for order in acc.orders_history)
    @test acc.balance == acc.equity

end
