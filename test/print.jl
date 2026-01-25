using Dates
using TestItemRunner

@testitem "Print Cash" begin
    using Test, Fastback
    show(Cash(:USD))
end

@testitem "Print Instrument" begin
    using Test, Fastback
    show(Instrument(Symbol("TEST/USD"), :TEST, :USD; margin_mode=MarginMode.PercentNotional))
end

@testitem "Print Order" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)
    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD; margin_mode=MarginMode.PercentNotional))
    price = 1000.0
    quantity = 1.0
    dt = DateTime(2021, 1, 1, 0, 0, 0)
    show(Order(oid!(acc), DUMMY, dt, price, quantity))
end

@testitem "Print Account" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)
    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD; margin_mode=MarginMode.PercentNotional))
    price = 1000.0
    quantity = 1.0
    dt = DateTime(2021, 1, 1, 0, 0, 0)
    order = Order(oid!(acc), DUMMY, dt, price, quantity)
    fill_order!(acc, order, dt, price; commission_pct=0.001)
    update_marks!(acc, DUMMY; dt=dt, bid=price, ask=price)
    show(acc)
end
