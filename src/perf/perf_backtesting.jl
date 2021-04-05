using Dates
using BenchmarkTools

include("../Fastback.jl");



# w/ delayed orders min     = 14.4 ms
# direct placement          = 5.4 ms
@benchmark begin
    AAPL = Instrument("AAPL");
    dt = DateTime(2018, 1, 2, 9, 30, 0)
    acc = Account(100_000.0)
    for i = 1:100_000
        nbbo = NBBO(dt, 100.0 + i / 1000, 102 + i / 1000)
        execute_order!(acc, OpenOrder(AAPL, 100), nbbo)
        update_account!(acc, AAPL, NBBO(dt, 100, 102))
        execute_order!(acc, CloseOrder(acc.open_positions[1]), nbbo)
        update_account!(acc, AAPL, NBBO(dt, 100, 102))
    end
end evals=3 samples=40


# w/ delayed orders min     = 2.1 ms
# direct placement          = 1.1 ms
@benchmark begin
    AAPL = Instrument("AAPL");
    dt = DateTime(2018, 1, 2, 9, 30, 0)
    acc = Account(100_000.0)
    for i = 1:100_000
        nbbo = NBBO(dt, 100.0 + i / 1000, 102 + i / 1000)
        if i == 1
            execute_order!(acc, OpenOrder(AAPL, 100), nbbo)
        end
        update_account!(acc, AAPL, nbbo)
    end
end evals=3 samples=40
