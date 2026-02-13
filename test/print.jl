using Dates
using TestItemRunner

@testitem "Print Cash" begin
    using Test, Fastback
    acc = Account(; base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    show(usd)
end

@testitem "Print Instrument" begin
    using Test, Fastback
    show(spot_instrument(Symbol("TEST/USD"), :TEST, :USD))
end

@testitem "Print Order" begin
    using Test, Fastback, Dates

    ledger = Fastback.CashLedger()
    base_currency=CashSpec(:USD)
    acc = Account(; mode=AccountMode.Margin, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)
    DUMMY = register_instrument!(acc, spot_instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))
    price = 1000.0
    quantity = 1.0
    dt = DateTime(2021, 1, 1, 0, 0, 0)
    show(Order(oid!(acc), DUMMY, dt, price, quantity))
end

@testitem "Print Account" begin
    using Test, Fastback, Dates

    ledger = Fastback.CashLedger()
    base_currency=CashSpec(:USD)
    acc = Account(; mode=AccountMode.Margin, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)
    DUMMY = register_instrument!(acc, spot_instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))
    price = 1000.0
    quantity = 1.0
    dt = DateTime(2021, 1, 1, 0, 0, 0)
    order = Order(oid!(acc), DUMMY, dt, price, quantity)
    fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price, commission_pct=0.001)
    update_marks!(acc, DUMMY, dt, price, price, price)
    show(acc)
end

@testitem "print_trades formats settlement currency" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    ledger = Fastback.CashLedger()
    base_currency=CashSpec(:EUR)
    acc = Account(; mode=AccountMode.Margin, base_currency=base_currency, exchange_rates=er)
    register_cash_asset!(acc, CashSpec(:USD; digits=4))
    deposit!(acc, :USD, 5_000.0)
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.2)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("FX/EURUSD"),
            :FX,
            :EUR;
            settle_symbol=:USD,
            settlement=SettlementStyle.Asset,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.0,
            margin_init_short=0.0,
            margin_maint_long=0.0,
            margin_maint_short=0.0,
        ),
    )

    dt = DateTime(2025, 1, 1)
    order = Order(oid!(acc), inst, dt, 10.0, 1.0)
    fill_order!(acc, order; dt=dt, fill_price=10.0, bid=10.0, ask=10.0, last=10.0, commission=2.0)

    buf = IOBuffer()
    io = IOContext(buf, :displaysize => (40, 200))
    print_trades(io, acc)
    output = String(take!(buf))
    output = replace(output, r"\e\[[0-9;]*m" => "") # strip ANSI color codes

    @test occursin("USD", output)           # settlement label
    @test occursin("Fill P&L", output)      # updated column header
    @test occursin("0.0000", output)        # P&L formatted with settle digits (gross, no commissions)
    @test occursin("-14.4000", output)      # cash delta formatted with settle digits
    @test occursin("2.4000", output)        # commission formatted with settle digits
end
