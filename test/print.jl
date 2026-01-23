using Dates
using TestItemRunner

@testitem "Print Cash" begin
    using Test, Fastback
    show(Cash(:USD))
end

@testitem "Print Instrument" begin
    using Test, Fastback
    show(Instrument(Symbol("TEST/USD"), :TEST, :USD))
end

@testitem "Print Order" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin)
    deposit!(acc, Cash(:USD), 10_000.0)
    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))
    price = 1000.0
    quantity = 1.0
    dt = DateTime(2021, 1, 1, 0, 0, 0)
    show(Order(oid!(acc), DUMMY, dt, price, quantity))
end

@testitem "Print Account" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin)
    deposit!(acc, Cash(:USD), 10_000.0)
    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))
    price = 1000.0
    quantity = 1.0
    dt = DateTime(2021, 1, 1, 0, 0, 0)
    order = Order(oid!(acc), DUMMY, dt, price, quantity)
    fill_order!(acc, order, dt, price; commission_pct=0.001)
    update_pnl!(acc, DUMMY, price, price)
    show(acc)
end
