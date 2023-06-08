using Fastback
using Test
using Dates


inst = Instrument("TICKER");

# generate data
data = Dict{Instrument,Vector{BidAsk}}();
dt = DateTime(2018, 1, 2, 9, 30, 0);
data[inst] = [
    BidAsk(dt + Second(1), 100.0, 101.0),
    BidAsk(dt + Second(2), 100.5, 102.0),
    BidAsk(dt + Second(3), 102.5, 103.0),
    BidAsk(dt + Second(4), 101.0, 102.0),
    BidAsk(dt + Second(5), 99.5, 100.0),
    BidAsk(dt + Second(6), 101.5, 102.0),
    BidAsk(dt + Second(7), 103.5, 104.0),
    BidAsk(dt + Second(8), 104.5, 105.0)
];


@testset "Dummy trading" begin

    # create trading account
    acc = Account(10_000.0)
    collect_balance, balance_curve = periodic_collector(Float64, Second(1))
    collect_equity, equity_curve = periodic_collector(Float64, Second(1))

    # dummy backtest
    for (i, ba) in enumerate(data[inst])
        if i == 1
            execute_order!(acc, OpenOrder(inst, 500.0, Long::TradeDir), ba)
        end

        update_account!(acc, inst, ba)

        if i == 7
            for i in length(acc.open_positions):-1:1
                pos = acc.open_positions[i]
                execute_order!(acc, CloseOrder(pos), ba)
            end
        end

        # collect data for analysis
        collect_balance(ba.dt, acc.balance)
        collect_equity(ba.dt, acc.equity)
    end

    # display(acc)

end


@testset "Dummy trading #2" begin

    # create trading account
    acc = Account(100_000.0)
    execute_order!(acc, OpenOrder(inst, 100.0, Long::TradeDir), data[inst][1])  # 100.0 101.0
    update_account!(acc, inst, data[inst][2]) # 100.5, 102.0
    execute_order!(acc, CloseOrder(acc.open_positions[1]), data[inst][3]) # 102.5, 103.0
    update_account!(acc, inst, data[inst][4]) # 101.0, 102.0

    # display(acc)

    p::Position = acc.closed_positions[1]
    @test p.open_price == 101.0
    @test p.last_price == 102.5

    @test pnl_gross(p) ≈ p.size * (midprice(p.last_quote) - midprice(p.open_quote))
    @test pnl_net(p) ≈ p.size * (p.last_price - p.open_price)

    @test return_gross(p) ≈ (midprice(p.last_quote) - midprice(p.open_quote)) / midprice(p.open_quote)
    @test return_net(p) ≈ (p.last_price - p.open_price) / p.open_price

    @test length(acc.open_positions) == 0
    @test length(acc.closed_positions) == 1
    @test acc.initial_balance == 100_000.0
    @test acc.equity ≈ acc.initial_balance + pnl_net(p)
    @test acc.balance ≈ acc.equity

end
