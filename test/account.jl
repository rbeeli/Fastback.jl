using Dates
using TestItemRunner

@testitem "Account long order w/o commission" begin
    using Test, Fastback, Dates
    # create trading account
    acc = Account()
    deposit!(acc, Cash(:USD), 100_000.0)

    @test cash_balance(acc, :USD) == 100_000.0
    @test equity(acc, :USD) == 100_000.0
    @test length(acc.cash) == 1
    # create instrument
    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))
    pos = get_position(acc, DUMMY)
    # generate data
    dates = collect(DateTime(2018, 1, 2):Day(1):DateTime(2018, 1, 4))
    prices = [100.0, 100.5, 102.5]
    # buy order
    qty = 100.0
    order = Order(oid!(acc), DUMMY, dates[1], prices[1], qty)
    exe1 = fill_order!(acc, order, dates[1], prices[1])
    @test exe1 == acc.trades[end]
    @test exe1.commission == 0.0
    @test nominal_value(exe1) == qty * prices[1]
    @test exe1.realized_pnl == 0.0
    # @test realized_return(exe1) == 0.0
    @test pos.avg_price == 100.0
    # update position and account P&L
    update_pnl!(acc, pos, prices[2])
    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ (prices[2] - prices[1]) * pos.quantity
    @test cash_balance(acc, :USD) ≈ 100_000.0
    @test equity(acc, :USD) ≈ 100_000.0 + (prices[2] - prices[1]) * pos.quantity
    # close position
    order = Order(oid!(acc), DUMMY, dates[3], prices[3], -pos.quantity)
    fill_order!(acc, order, dates[3], prices[3])
    # update position and account P&L
    update_pnl!(acc, pos, prices[3])
    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ 0
    @test cash_balance(acc, :USD) ≈ 100_000.0 + (prices[3] - prices[1]) * qty
    @test equity(acc, :USD) ≈ cash_balance(acc, :USD)
    show(acc)
end

@testitem "Deposit & withdraw cash" begin
    using Test, Fastback

    acc = Account()
    usd = Cash(:USD)

    deposit!(acc, usd, 1_000.0)
    @test cash_balance(acc, usd) == 1_000.0
    @test equity(acc, usd) == 1_000.0

    withdraw!(acc, usd, 400.0)
    @test cash_balance(acc, usd) == 600.0
    @test equity(acc, usd) == 600.0
end

@testitem "Account long order w/ commission ccy" begin
    using Test, Fastback, Dates
    # create trading account
    acc = Account()
    deposit!(acc, Cash(:USD), 100_000.0)

    @test cash_balance(acc, :USD) == 100_000.0
    @test equity(acc, :USD) == 100_000.0
    @test length(acc.cash) == 1
    # create instrument
    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))
    pos = get_position(acc, DUMMY)
    # generate data
    dates = collect(DateTime(2018, 1, 2):Day(1):DateTime(2018, 1, 4))
    prices = [100.0, 100.5, 102.5]
    # buy order
    qty = 100.0
    order = Order(oid!(acc), DUMMY, dates[1], prices[1], qty)
    commission = 1.0
    exe1 = fill_order!(acc, order, dates[1], prices[1]; commission=commission)
    @test exe1 == acc.trades[end]
    @test nominal_value(exe1) == qty * prices[1]
    @test exe1.commission == commission
    @test exe1.realized_pnl == -commission
    # @test realized_return(exe1) == 0.0
    @test pos.avg_price == 100.0
    # update position and account P&L
    update_pnl!(acc, pos, prices[2])

    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ (prices[2] - prices[1]) * pos.quantity # does not include commission!
    @test cash_balance(acc, :USD) ≈ 100_000.0 - commission
    @test equity(acc, :USD) ≈ 100_000.0+ (prices[2] - prices[1]) * pos.quantity - commission
    # close position
    order = Order(oid!(acc), DUMMY, dates[3], prices[3], -pos.quantity)
    exe2 = fill_order!(acc, order, dates[3], prices[3]; commission=0.5)
    # update position and account P&L
    update_pnl!(acc, pos, prices[3])
    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ 0
    @test cash_balance(acc, :USD) ≈ 100_000.0 + (prices[3] - prices[1]) * qty - commission - 0.5
    @test equity(acc, :USD) ≈ cash_balance(acc, :USD)
    show(acc)
end

@testitem "Account long order w/ commission pct" begin
    using Test, Fastback, Dates
    # create trading account
    acc = Account();
    deposit!(acc, Cash(:USD), 100_000.0)
    @test cash_balance(acc, :USD) == 100_000.0
    @test equity(acc, :USD) == 100_000.0
    @test length(acc.cash) == 1
    # create instrument
    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))
    pos = get_position(acc, DUMMY)
    # generate data
    dates = collect(DateTime(2018, 1, 2):Day(1):DateTime(2018, 1, 4))
    prices = [100.0, 100.5, 102.5]
    # buy order
    qty = 100.0
    order = Order(oid!(acc), DUMMY, dates[1], prices[1], qty)
    commission_pct1 = 0.001
    exe1 = fill_order!(acc, order, dates[1], prices[1]; commission_pct=commission_pct1)
    @test nominal_value(exe1) == qty * prices[1]
    @test exe1.commission == commission_pct1*nominal_value(exe1)
    @test acc.trades[end].realized_pnl == -commission_pct1*nominal_value(exe1)
    # @test realized_return(acc.trades[end]) == 0.0
    @test pos.avg_price == 100.0
    # update position and account P&L
    update_pnl!(acc, pos, prices[2])

    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ (prices[2] - prices[1]) * pos.quantity # does not include commission!
    @test cash_balance(acc, :USD) ≈ 100_000.0 - exe1.commission
    @test equity(acc, :USD) ≈ 100_000.0+ (prices[2] - prices[1]) * pos.quantity - exe1.commission
    # close position
    order = Order(oid!(acc), DUMMY, dates[3], prices[3], -pos.quantity)
    exe2 = fill_order!(acc, order, dates[3], prices[3]; commission_pct=0.0005)
    # update position and account P&L
    update_pnl!(acc, pos, prices[3])
    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ 0
    @test cash_balance(acc, :USD) ≈ 100_000.0 + (prices[3] - prices[1]) * qty - exe1.commission - exe2.commission
    @test equity(acc, :USD) ≈ cash_balance(acc, :USD)
    show(acc)
end

@testitem "Commission pct uses instrument multiplier" begin
    using Test, Fastback, Dates

    acc = Account()
    deposit!(acc, Cash(:USD), 100_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("MULTI/USD"), :MULTI, :USD; multiplier=10.0))

    dates = collect(DateTime(2018, 1, 2):Day(1):DateTime(2018, 1, 3))
    price = 100.0
    qty = 2.0
    order = Order(oid!(acc), inst, dates[1], price, qty)
    commission_pct = 0.001
    trade = fill_order!(acc, order, dates[1], price; commission_pct=commission_pct)

    expected_nominal = qty * price * inst.multiplier
    @test nominal_value(order) == expected_nominal
    @test nominal_value(trade) == expected_nominal
    @test trade.commission == commission_pct * expected_nominal
end

@testitem "Spot long asset-settled valuation" begin
    using Test, Fastback, Dates

    acc = Account()
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("SPOT/USD"), :SPOT, :USD; settlement=SettlementStyle.Asset))
    pos = get_position(acc, inst)

    dt = DateTime(2021, 1, 1)
    price = 50.0
    qty = 100.0
    order = Order(oid!(acc), inst, dt, price, qty)
    fill_order!(acc, order, dt, price)

    @test cash_balance(acc, :USD) ≈ 5_000.0
    @test pos.value_local ≈ 5_000.0
    @test equity(acc, :USD) ≈ 10_000.0

    update_pnl!(acc, pos, 60.0)
    @test pos.value_local ≈ 6_000.0
    @test equity(acc, :USD) ≈ 11_000.0
end

@testitem "Spot short asset-settled valuation" begin
    using Test, Fastback, Dates

    acc = Account()
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("SPOT/USD"), :SPOT, :USD; settlement=SettlementStyle.Asset))
    pos = get_position(acc, inst)

    dt = DateTime(2021, 1, 1)
    price = 50.0
    qty = -100.0
    order = Order(oid!(acc), inst, dt, price, qty)
    fill_order!(acc, order, dt, price)

    @test cash_balance(acc, :USD) ≈ 15_000.0
    @test pos.value_local ≈ -5_000.0
    @test equity(acc, :USD) ≈ 10_000.0

    update_pnl!(acc, pos, 60.0)
    @test pos.value_local ≈ -6_000.0
    @test equity(acc, :USD) ≈ 9_000.0
end


@testitem "Account with Date timestamps" begin
    using Test, Fastback, Dates, Tables

    acc = Account(; time_type=Date, date_format=dateformat"yyyy-mm-dd")
    deposit!(acc, Cash(:USD), 1_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("DATE/USD"), :DATE, :USD))

    d₁ = Date(2020, 1, 1)
    order₁ = Order(oid!(acc), inst, d₁, 10.0, 1.0)
    fill_order!(acc, order₁, d₁, 10.0)

    d₂ = Date(2020, 1, 2)
    order₂ = Order(oid!(acc), inst, d₂, 9.5, -1.0)
    fill_order!(acc, order₂, d₂, 9.5)

    @test all(t.date isa Date for t in acc.trades)

    tbl = trades_table(acc)
    schema = Tables.schema(tbl)
    @test schema.types[3] == Date
    rows = collect(Tables.rows(tbl))
    @test rows[1].trade_date isa Date
    @test rows[end].order_date == d₂
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

#     @test pos.pnl_local ≈ -100
#     @test total_balance(acc) ≈ 100_000.0 - pos.quantity * prices[1].bid
#     @test total_equity(acc) ≈ 99_900.0

#     update_book!(book, prices[2])
#     update_account!(acc, data, inst)

#     @test pos.pnl_local ≈ -200
#     @test total_balance(acc) ≈ 100_000.0 - pos.quantity * prices[1].bid
#     @test total_equity(acc) ≈ 99_800.0

#     update_book!(book, prices[3])
#     update_account!(acc, data, inst)

#     # open long order (results in net long +100)
#     execute_order!(acc, book, Order(inst, 200.0, prices[3].dt))

#     @test acc.positions[inst.index].avg_price == book.bba.ask
#     @test realized_return(acc.trades[end].execution) ≈ (100.0 - 103.0) / 100.0
#     @test realized_pnl(acc.trades[end].execution) ≈ -300.0
#     # @test calc_realized_return(acc.trades[end].execution) ≈ (100.0 - 103.0) / 100.0
#     @test acc.trades[end].execution.realized_pnl ≈ -300.0
#     @test pos.pnl_local ≈ -50
#     @test total_balance(acc) ≈ 100_000.0 + sum(t.execution.realized_pnl for t in acc.trades) - pos.quantity * prices[3].ask
#     @test total_equity(acc) ≈ 99_650.0

#     update_book!(book, prices[4])
#     update_account!(acc, data, inst)

#     @test total_equity(acc) ≈ 99_400.0

#     # open short order (results in net short -50)
#     execute_order!(acc, book, Order(inst, -150.0, prices[4].dt))

#     @test acc.positions[inst.index].avg_price == book.bba.bid
#     @test acc.trades[end].execution.realized_pnl ≈ -300.0
#     @test pos.pnl_local ≈ -25
#     @test total_balance(acc) ≈ 100_000.0 + sum(t.execution.realized_pnl for t in acc.trades) - pos.quantity * prices[4].bid
#     @test total_equity(acc) ≈ 99_375.0

#     # close open position
#     execute_order!(acc, book, Order(inst, 50.0, prices[4].dt))

#     @test total_balance(acc) ≈ 99_375.0
#     @test total_equity(acc) ≈ 99_375.0
#     @test acc.trades[end].execution.realized_pnl ≈ -25.0

#     @test pos.quantity == 0.0
#     @test pos.avg_price == 0.0
#     @test pos.pnl_local == 0.0
#     @test length(pos.trades) == 4

#     @test total_equity(acc) == 100_000.0+ sum(t.execution.realized_pnl for t in acc.trades)
#     @test total_balance(acc) == total_equity(acc)

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
