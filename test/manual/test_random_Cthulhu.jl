using Dates, Fastback
using Cthulhu

function run(dates::Vector{DateTime}, bids::Vector{Float64}, asks::Vector{Float64})
    # create instrument
    inst = Instrument(1, "AAPL")
    insts = [inst]

    # market data (order books)
    data = MarketData(insts)

    # create trading account
    acc = Account(insts, 100_000.0)

    pos = acc.positions[inst.index]

    # backtest random trading strategy
    N = length(dates)
    for i in 1:N
        dt = dates[i]
        book = data.order_books[inst.index]
        update_book!(book, BidAsk(dates[i], bids[i], asks[i]))

        if i == N
            # close all orders at end of backtest
            if pos.quantity !== 0.0
                execute_order!(acc, book, Order(inst, -pos.quantity, dt))
            end
        else
            # randomly trade
            if rand() > 0.999
                sgn = rand() >= 0.5 ? 1.0 : -1.0
                execute_order!(acc, book, Order(inst, sgn, dt))
            end
        end

        update_account!(acc, data, inst)
    end
end

# synthetic data
N = 100_000
prices = 1000.0 .+ cumsum(randn(N) .+ 0.01)
bids = prices .- 0.01
asks = prices .+ 0.01
dts = map(x -> DateTime(2000, 1, 1) + Minute(x) + Millisecond(123), 1:N);

@descend run(dts, bids, asks)