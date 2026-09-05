using Dates
using TestItemRunner

@testitem "Print Cash" begin
    using Test, Fastback
    acc = Account(; broker=NoOpBroker(), base_currency=CashSpec(:USD))
    usd = cash_asset(acc, :USD)
    show(usd)
end

@testitem "Text tables crop rows before formatting" begin
    using Test, Fastback

    for limit in (0, 1, 3, 4, -1)
        seen = Int[]
        buf = IOBuffer()
        cell = (i, j) -> (push!(seen, i); ("record-$i", nothing))
        Fastback._print_text_table(buf, ["Record"], 8; cell, max_rows=limit)
        output = String(take!(buf))
        expected = limit < 0 ? collect(1:8) : vcat(1:cld(limit, 2), (9 - fld(limit, 2)):8)
        @test seen == expected
        @test occursin("rows omitted", output) == (limit >= 0)

        for i in setdiff(1:8, expected)
            @test !occursin("record-$i", output)
        end
    end

    # A large history must not format the omitted rows.
    calls = Ref(0)
    cell = (i, j) -> (calls[] += 1; (i, nothing))
    Fastback._print_text_table(IOBuffer(), ["ID"], 1_000_000; cell, max_rows=5)
    @test calls[] == 5
end

@testitem "Text tables align Unicode and respect terminal width" begin
    using Test, Fastback

    values = ["東京" "1.25"; "e\u0301" "-12.50"; "line\n\t\e" "NaN"]
    cell = (i, j) -> (values[i, j], nothing)

    for width in (0, 1, 4, 5, 8, 9, 12, 20, 80)
        buf = IOBuffer()
        io = IOContext(buf, :displaysize => (2, width))
        Fastback._print_text_table(io, ["Symbol", "P&L"], 3; cell)
        output = String(take!(buf))
        lines = split(chomp(output), '\n'; keepempty=false)
        @test all(textwidth(line) <= width for line in lines)
        @test !occursin('\e', output)

        if width == 80
            @test length(unique(textwidth.(lines))) == 1
            @test occursin("東京", output)
            @test occursin("e\u0301", output)
            @test occursin("line\\n\\t\\e", output)
            @test length(lines) == 7 # No vertical crop to the terminal height.
        elseif width > 0
            @test occursin('…', output)
        end
    end

    buf = IOBuffer()
    Fastback._print_text_table(buf, ["Empty"], 0; cell=(i, j) -> error("No rows"))
    @test occursin("Empty", String(take!(buf)))

    # Even when the first column fits, hidden columns need an omission marker.
    buf = IOBuffer()
    Fastback._print_text_table(IOContext(buf, :displaysize => (20, 8)), ["A", "B"], 1;
        cell=(i, j) -> (j, nothing))
    @test occursin('…', String(take!(buf)))
end

@testitem "Account text rendering preserves colors and plain output" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=CashSpec(:USD))
    deposit!(acc, :USD, 10_000.0)
    dt = DateTime(2025, 1, 1)

    for (name, quantity) in ((:LONG, 2.0), (:SHORT, -2.0))
        inst = register_instrument!(acc, spot_instrument(name, name, :USD))
        order = Order(oid!(acc), inst, dt, 100.0, quantity)
        fill_order!(acc, order; dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    end

    for pos in acc.positions
        update_marks!(acc, pos, dt + Day(1), 105.0, 105.0, 105.0)
    end

    for render in (show, print_positions, print_trades, print_cash_balances, print_equity_balances)
        plain = sprint(io -> render(io, acc); context=(:color => false, :displaysize => (40, 300)))
        colored = sprint(io -> render(io, acc); context=(:color => true, :displaysize => (40, 300)))
        @test !occursin('\e', plain)
        @test occursin("\e[", colored)
        @test replace(colored, r"\e\[[0-9;]*m" => "") == plain
    end

    positions = sprint(io -> print_positions(io, acc); context=:color => true)
    @test occursin("\e[38;2;17;191;17m10.00\e[0m", positions)
    @test occursin("\e[38;2;221;0;0m-10.00\e[0m", positions)
    @test occursin("\e[38;2;221;0;221m", positions)
    @test occursin("\e[38;2;221;221;0m", positions)
    @test equity_base_ccy(acc) == 10_000.0
    @test Fastback.check_invariants(acc)

    # Narrow terminals should not make the account heading throw.
    @test !isempty(sprint(show, acc; context=:displaysize => (5, 8)))
end

@testitem "Cashflow text rendering preserves signs and cash precision" begin
    using Test, Fastback, Dates

    acc = Account(; broker=NoOpBroker(), base_currency=CashSpec(:USD; digits=4))
    dt = DateTime(2025, 1, 1)
    # Display-only history fixture, including an unassociated instrument.
    push!(acc.cashflows, Cashflow(1, dt, CashflowKind.Other, 1, 1.25, 0))
    push!(acc.cashflows, Cashflow(2, dt, CashflowKind.Other, 1, -2.5, 0))
    push!(acc.cashflows, Cashflow(3, dt, CashflowKind.Other, 1, 0.0, 0))
    plain = sprint(io -> print_cashflows(io, acc); context=:color => false)
    colored = sprint(io -> print_cashflows(io, acc); context=:color => true)
    @test !occursin('\e', plain)
    @test replace(colored, r"\e\[[0-9;]*m" => "") == plain
    @test occursin("\e[38;2;17;191;17m1.2500\e[0m", colored)
    @test occursin("\e[38;2;221;0;0m-2.5000\e[0m", colored)
    @test occursin("0.0000", plain)
    @test occursin("—", plain)
    @test occursin("2 rows omitted", sprint(io -> print_cashflows(io, acc; max_print=1)))
end

@testitem "Exchange rates render labeled directional values" begin
    using Test, Fastback

    er = ExchangeRates()
    @test sprint(show, er) == "No exchange rates available.\n"
    update_rate!(er, 1, 2, 2.0)
    output = sprint(show, er)
    @test occursin("│ 1 │ 1.0 │ 2.0 │", output)
    @test occursin("│ 2 │ 0.5 │ 1.0 │", output)
    @test !occursin('\e', output)
end

@testitem "Print Instrument" begin
    using Test, Fastback
    show(spot_instrument(Symbol("TEST/USD"), :TEST, :USD))
end

@testitem "Print Order" begin
    using Test, Fastback, Dates

    ledger = Fastback.CashLedger()
    base_currency=CashSpec(:USD)
    acc = Account(; funding=AccountFunding.Margined, base_currency=base_currency, broker=FlatFeeBroker(pct=0.001))
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
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)
    DUMMY = register_instrument!(acc, spot_instrument(Symbol("DUMMY/USD"), :DUMMY, :USD))
    price = 1000.0
    quantity = 1.0
    dt = DateTime(2021, 1, 1, 0, 0, 0)
    order = Order(oid!(acc), DUMMY, dt, price, quantity)
    fill_order!(acc, order; dt=dt, fill_price=price, bid=price, ask=price, last=price)
    update_marks!(acc, DUMMY, dt, price, price, price)
    show(acc)
end

@testitem "print_trades formats settlement currency" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    ledger = Fastback.CashLedger()
    base_currency=CashSpec(:EUR)
    acc = Account(; funding=AccountFunding.Margined, base_currency=base_currency, exchange_rates=er, broker=FlatFeeBroker(fixed=2.0))
    register_cash_asset!(acc, CashSpec(:USD; digits=4))
    deposit!(acc, :USD, 5_000.0)
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.2)

    inst = register_instrument!(
        acc,
        InstrumentSpec(
            Symbol("FX/EURUSD"),
            :FX,
            :EUR;
            settle_symbol=:USD,
            settlement=SettlementStyle.PrincipalExchange,
            margin_requirement=MarginRequirement.PercentNotional,
            margin_init_long=0.0,
            margin_init_short=0.0,
            margin_maint_long=0.0,
            margin_maint_short=0.0,
        ),
    )

    dt = DateTime(2025, 1, 1)
    order = Order(oid!(acc), inst, dt, 10.0, 1.0)
    fill_order!(acc, order; dt=dt, fill_price=10.0, bid=10.0, ask=10.0, last=10.0)

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
