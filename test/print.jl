using Fastback
using Test
using Dates

@testset "Print Cash" begin
    show(Cash(:USD))
end

@testset "Print Instrument" begin
    show(Instrument(Symbol("TEST/USD"), :TEST, :USD))
end

@testset "Print Order" begin
    acc = Account()
    add_cash!(acc, Cash(:USD), 10_000.0)

    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))

    price = 1000.0
    quantity = 1.0
    dt = DateTime(2021, 1, 1, 0, 0, 0)
    show(Order(oid!(acc), DUMMY, dt, price, quantity))
end

@testset "Print Account" begin
    acc = Account()
    add_cash!(acc, Cash(:USD), 10_000.0)

    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))

    price = 1000.0
    quantity = 1.0
    dt = DateTime(2021, 1, 1, 0, 0, 0)
    order = Order(oid!(acc), DUMMY, dt, price, quantity)
    fill_order!(acc, order, dt, price; commission_pct=0.001)

    update_pnl!(acc, DUMMY, price, price)

    show(acc)
end
