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

    @test acc.initial_balance == 100_000.0
    @test acc.balance == 100_000.0
    @test acc.equity == 100_000.0

    # generate data
    prices = [
        BidAsk(DateTime(2018, 1, 2, 0, 0, 0), 100.0, 101.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 1), 100.5, 102.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 2), 102.5, 103.0),
    ]

    # update order book
    update_book!(book, prices[1])

    # open long order
    execute_order!(acc, book, Order(inst, 100.0, prices[1].dt))

    @test calc_realized_pnl(acc.transactions[end].execution) == 0.0
    @test calc_realized_price_return(acc.transactions[end].execution) == 0.0
    @test acc.positions[inst.index].avg_price == 101.0

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

    @test calc_realized_pnl(acc.transactions[end].execution) == 150
    @test calc_realized_price_return(acc.transactions[end].execution) ≈ (102.5 - 101.0) / 101.0
    @test acc.positions[inst.index].transactions[end].execution.realized_pnl ≈ 150

    @test acc.positions[inst.index].quantity == 0.0
    @test acc.positions[inst.index].avg_price == 0.0
    @test acc.positions[inst.index].pnl == 0.0
    @test length(acc.positions[inst.index].transactions) == 2

    @test acc.balance ≈ 100_150.0
    @test acc.equity ≈ 100_150.0

    @test acc.equity == acc.initial_balance + sum(tx.execution.realized_pnl for tx in acc.transactions)
    @test acc.balance == acc.equity

    show(acc)
end

@testset "Single ticker + collectors" begin
    # create instrument
    inst = Instrument(1, "TICKER")
    insts = [inst]

    # generate data
    data = Dict{Instrument,Vector{BidAsk}}()
    data[inst] = [
        BidAsk(DateTime(2018, 1, 2, 0, 0, 0), 100.0, 101.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 1), 100.5, 102.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 2), 102.5, 103.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 3), 101.0, 102.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 4), 99.5, 100.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 5), 101.5, 102.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 6), 103.5, 104.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 7), 104.5, 105.0),
    ]

    # market data (order books)
    market_data = MarketData(insts)
    book = market_data.order_books[inst.index]

    # create trading account
    acc = Account(insts, 10_000.0)
    collect_balance, balance_curve = periodic_collector(Float64, Second(1))
    collect_equity, equity_curve = periodic_collector(Float64, Second(1))

    # dummy backtest
    for (i, ba) in enumerate(data[inst])
        update_book!(book, ba)
        update_account!(acc, market_data, inst)

        if i == 1
            execute_order!(acc, book, Order(inst, 500.0, ba.dt))
            @test acc.positions[inst.index].avg_price == book.bba.ask
        end

        if i == 7
            execute_order!(acc, book, Order(inst, -acc.positions[inst.index].quantity, ba.dt))
            @test acc.positions[inst.index].avg_price == 0.0
        end

        # collect data for analysis
        collect_balance(ba.dt, acc.balance)
        collect_equity(ba.dt, acc.equity)
    end

    @test length(balance_curve.values) == 8
    @test length(equity_curve.values) == 8
    @test equity_curve.values[end][2] == acc.equity
    @test balance_curve.values[end][2] == acc.balance

    @test length(acc.transactions) == 2
    @test acc.transactions[1].execution.quantity == 500.0

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
    prices = [
        BidAsk(DateTime(2018, 1, 2, 0, 0, 0), 100.0, 101.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 1), 100.5, 102.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 2), 102.5, 103.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 3), 100.0, 100.5),
    ]

    pos = acc.positions[inst.index]

    update_book!(book, prices[1])

    execute_order!(acc, book, Order(inst, -100.0, prices[1].dt))
    @test acc.positions[inst.index].avg_price == book.bba.bid

    update_account!(acc, data, inst)

    @test pos.pnl ≈ -100
    @test acc.balance ≈ 100_000.0 - pos.quantity * prices[1].bid
    @test acc.equity ≈ 99_900.0

    update_book!(book, prices[2])
    update_account!(acc, data, inst)

    @test pos.pnl ≈ -200
    @test acc.balance ≈ 100_000.0 - pos.quantity * prices[1].bid
    @test acc.equity ≈ 99_800.0

    update_book!(book, prices[3])
    update_account!(acc, data, inst)

    # open long order (results in net long +100)
    execute_order!(acc, book, Order(inst, 200.0, prices[3].dt))

    @test acc.positions[inst.index].avg_price == book.bba.ask
    @test calc_realized_price_return(acc.transactions[end].execution) ≈ (100.0 - 103.0) / 100.0
    @test calc_realized_pnl(acc.transactions[end].execution) ≈ -300.0
    # @test calc_realized_return(acc.transactions[end].execution) ≈ (100.0 - 103.0) / 100.0
    @test acc.transactions[end].execution.realized_pnl ≈ -300.0
    @test pos.pnl ≈ -50
    @test acc.balance ≈ 100_000.0 + sum(t.execution.realized_pnl for t in acc.transactions) - pos.quantity * prices[3].ask
    @test acc.equity ≈ 99_650.0

    update_book!(book, prices[4])
    update_account!(acc, data, inst)

    @test acc.equity ≈ 99_400.0

    # open short order (results in net short -50)
    execute_order!(acc, book, Order(inst, -150.0, prices[4].dt))

    @test acc.positions[inst.index].avg_price == book.bba.bid
    @test acc.transactions[end].execution.realized_pnl ≈ -300.0
    @test pos.pnl ≈ -25
    @test acc.balance ≈ 100_000.0 + sum(t.execution.realized_pnl for t in acc.transactions) - pos.quantity * prices[4].bid
    @test acc.equity ≈ 99_375.0

    # close open position
    execute_order!(acc, book, Order(inst, 50.0, prices[4].dt))

    @test acc.balance ≈ 99_375.0
    @test acc.equity ≈ 99_375.0
    @test acc.transactions[end].execution.realized_pnl ≈ -25.0

    @test pos.quantity == 0.0
    @test pos.avg_price == 0.0
    @test pos.pnl == 0.0
    @test length(pos.transactions) == 4

    @test acc.equity == acc.initial_balance + sum(t.execution.realized_pnl for t in acc.transactions)
    @test acc.balance == acc.equity

    # realized_orders = filter(t -> t.execution.realized_pnl != 0.0, acc.transactions)
    # @test equity_return(acc) ≈ sum(calc_realized_return(o)*o.execution.weight for o in realized_orders)
end


@testset "Backtesting single ticker avg_price" begin
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
    prices = [
        BidAsk(DateTime(2018, 1, 2, 0, 0, 0), 100.0, 101.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 1), 100.5, 102.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 2), 102.5, 103.0),
        BidAsk(DateTime(2018, 1, 2, 0, 0, 3), 100.0, 100.5),
    ]

    pos = acc.positions[inst.index]

    update_book!(book, prices[1])
    update_account!(acc, data, inst)

    # buy order (net long +100)
    execute_order!(acc, book, Order(inst, 100.0, prices[1].dt))
    @test acc.positions[inst.index].avg_price == prices[1].ask

    update_book!(book, prices[2])
    update_account!(acc, data, inst)

    # sell order (reduce exposure to net long +50)
    execute_order!(acc, book, Order(inst, -50.0, prices[2].dt))
    @test acc.positions[inst.index].avg_price == prices[1].ask

    update_book!(book, prices[3])
    update_account!(acc, data, inst)

    # flip exposure (net short -50)
    execute_order!(acc, book, Order(inst, -100.0, prices[3].dt))
    @test acc.positions[inst.index].avg_price == prices[3].bid

    update_book!(book, prices[4])
    update_account!(acc, data, inst)

    # close all positions
    execute_order!(acc, book, Order(inst, 50.0, prices[4].dt))
    @test acc.positions[inst.index].avg_price == 0.0
end
