using Fastback
using Dates
using Test

@testset "Backtesting" begin

    # create instrument
    inst = Instrument("TICKER")

    # generate data
    dt = DateTime(2018, 1, 2, 9, 30, 0)
    prices = [
        BidAsk(dt + Second(1), 100.0, 101.0),
        BidAsk(dt + Second(2), 100.5, 102.0),
        BidAsk(dt + Second(3), 102.5, 103.0)
    ]

    # create trading account
    acc = Account(100_000.0)

    @test acc.initial_balance == 100_000.0
    @test acc.balance == 100_000.0
    @test acc.equity == 100_000.0

    # open long order
    execute_order!(acc, OpenOrder(inst, 100.0, Long), prices[1])

    # update account info
    update_account!(acc, inst, prices[1])
    acc

    @test pnl_net(acc.open_positions[1]) ≈ -100
    @test pnl_gross(acc.open_positions[1]) ≈ 0
    @test acc.balance ≈ 100_000.0
    @test acc.equity ≈ 99_900.0

    # update account info with new price
    update_account!(acc, inst, prices[2])
    acc

    @test pnl_net(acc.open_positions[1]) ≈ -50
    @test pnl_gross(acc.open_positions[1]) ≈ 75
    @test acc.balance ≈ 100_000.0
    @test acc.equity ≈ 99_950.0

    # close order again
    execute_order!(acc, CloseOrder(acc.open_positions[1]), prices[3])

    # update account info
    update_account!(acc, inst, prices[3])
    acc


    @test pnl_net(acc.closed_positions[1]) ≈ 150
    @test pnl_gross(acc.closed_positions[1]) ≈ 225
    @test acc.balance ≈ 100_150.0
    @test acc.equity ≈ 100_150.0

end
