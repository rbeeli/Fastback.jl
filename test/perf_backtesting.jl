using Dates
using BenchmarkTools
using Fastback

# w/ delayed orders min     = 14.4 ms
# direct placement          = 5.4 ms
@benchmark begin
    AAPL = Instrument("AAPL");
    dt = DateTime(2018, 1, 2, 9, 30, 0)
    acc = Account(100_000.0)
    for i = 1:100_000
        ba = BidAsk(dt, 100.0 + i / 1000, 102 + i / 1000)
        execute_order!(acc, OpenOrder(AAPL, 100.0, Long), ba)
        update_account!(acc, AAPL, BidAsk(dt, 100.0, 102.0))
        execute_order!(acc, CloseOrder(acc.open_positions[1]), ba)
        update_account!(acc, AAPL, BidAsk(dt, 100.0, 102.0))
    end
end evals=3 samples=40


# w/ delayed orders min     = 2.1 ms
# direct placement          = 1.1 ms
@benchmark begin
    AAPL = Instrument("AAPL");
    dt = DateTime(2018, 1, 2, 9, 30, 0)
    acc = Account(100_000.0)
    for i = 1:100_000
        ba = BidAsk(dt, 100.0 + i / 1000, 102 + i / 1000)
        if i == 1
            execute_order!(acc, OpenOrder(AAPL, 100.0, Long), ba)
        end
        update_account!(acc, AAPL, ba)
    end
end evals=3 samples=40
