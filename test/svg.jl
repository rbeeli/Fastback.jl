using TestItemRunner

@testitem "SVG plots render through Charts" begin
    using Fastback, Dates
    S = Fastback
    collect_eq, eq = periodic_collector(Float64, Day(1))
    collect_dd, dd = drawdown_collector(DrawdownMode.Percentage, Day(1))

    for (i, v) in enumerate([100.0, 120.0, 90.0, 110.0])
        dt = DateTime(2025) + Day(i)
        collect_eq(dt, v)
        collect_dd(dt, v)
    end

    options = S.Charts.ChartOptions(; title="Equity", legend=nothing)
    expected = S.Charts.render_svg_line_chart(
        [S.Charts.LineSeries("Equity", dates(eq), values(eq); color=S._PLOT_COLORS.equity)], options)
    @test S.plot_equity(eq; output_format=:string) == expected

    for name in (:balance, :equity, :open_orders_count, :drawdown, :equity_drawdown,
        :exposure, :portfolio_weights_over_time)
        args = name === :drawdown ? (dd,) : name === :equity_drawdown ? (eq, dd) :
            name === :exposure ? () :
            name === :portfolio_weights_over_time ? (dates(eq), fill(0.5, 4, 2), ["A", "B"]) : (eq,)
        kwargs = name === :exposure ? (; gross=eq, net=eq) : (;)
        svg = getfield(S, Symbol(:plot_, name))(args...; output_format=:string, kwargs...)
        io = IOBuffer()
        @test getfield(S, Symbol(:plot_, name, :!))(io, args...; kwargs...) === io
        @test String(take!(io)) == svg
        @test occursin("<svg xmlns=", svg)
        @test occursin(S.Charts.DARK_PLOT_THEME.canvas, svg)
        @test !occursin(r"NaN|Inf", svg)
    end

    @test occursin("Max drawdown", S.plot_equity_drawdown(eq, dd; legend=true, output_format=:string))
    @test !occursin("Max drawdown", S.plot_equity_drawdown(eq, dd; legend=true, show_max_dd=false, output_format=:string))
    @test occursin("%", S.plot_drawdown(dd; output_format=:string))
    @test !occursin("2025-", S.plot_equity(eq; xaxis_mode=:index, output_format=:string))
    @test occursin("font-size=\"16\">Gross</text>", S.plot_exposure(; gross=eq, output_format=:string))
    @test !occursin("font-size=\"16\">Gross</text>", S.plot_exposure(; gross=eq, legend=false, output_format=:string))
    @test_throws ArgumentError S.plot_equity(eq; xaxis_mode=:invalid)
    @test_throws ArgumentError S.plot_equity(eq; width=0)
    @test_throws ArgumentError S.plot_equity(eq; ylims=(1, 1))
    @test_throws ArgumentError S.plot_portfolio_weights_over_time(dates(eq), ones(3, 2), ["A", "B"])
    @test_throws ArgumentError S.plot_portfolio_weights_over_time(dates(eq), fill(NaN, 4, 2), ["A", "B"])
    @test_throws ArgumentError S.plot_title("Plots only"; backend=:svg)

    _, empty = periodic_collector(Float64, Day(1))
    @test_throws ArgumentError S.plot_equity(empty)
end

@testitem "SVG global output format" begin
    using Fastback, Dates
    S = Fastback
    previous = S.svg_output_format()
    collect_eq, eq = periodic_collector(Float64, Day(1))
    collect_eq(DateTime(2025), 100.0)
    try
        @test S.set_svg_output_format!(:string) === :string
        raw = S.plot_equity(eq)
        @test raw isa String
        @test S.set_svg_output_format!(:html) === :html
        html = S.plot_equity(eq)
        @test html isa Base.HTML
        @test repr(MIME"text/html"(), html) == raw
        @test S.plot_equity(eq; output_format=:string) == raw
        @test_throws ArgumentError S.set_svg_output_format!(:invalid)
        @test S.svg_output_format() === :html
        @test_throws ArgumentError S.plot_equity(eq; output_format=:invalid)
    finally
        S.set_svg_output_format!(previous)
    end
end

@testitem "SVG drawdown markers respect the drawdown mode" begin
    using Fastback, Dates
    S = Fastback
    collect_eq, eq = periodic_collector(Float64, Day(1))

    for (i, v) in enumerate([100.0, 120.0, 90.0, 50.0, 200.0, 220.0, 180.0, 140.0])
        collect_eq(DateTime(2025) + Day(i), v)
    end

    marker_x = Dict{DrawdownMode.T,Vector{Float64}}()

    for mode in (DrawdownMode.Percentage, DrawdownMode.PnL)
        collect_dd, dd = drawdown_collector(mode, Day(1))

        for (dt, v) in zip(dates(eq), values(eq))
            collect_dd(dt, v)
        end

        svg = S.plot_equity_drawdown(eq, dd; xaxis_mode=:index, output_format=:string)
        xs = [parse(Float64, m.captures[1]) for m in eachmatch(r"<circle class=\"line-point\"[^>]* cx=\"([^\"]+)\"", svg)]
        @test length(xs) == 2
        marker_x[mode] = xs
        @test !occursin("line-point", S.plot_equity_drawdown(eq, dd; show_max_dd=false, output_format=:string))
    end

    # The 58% decline occurs before the larger absolute loss of 80.
    @test marker_x[DrawdownMode.Percentage][1] < marker_x[DrawdownMode.Percentage][2] <
          marker_x[DrawdownMode.PnL][1] < marker_x[DrawdownMode.PnL][2]

    for (vals, has_drawdown) in (([100.0, 110.0], false), ([100.0, NaN, 50.0], true))
        collect_p, p = periodic_collector(Float64, Day(1))
        collect_dd, dd = drawdown_collector(DrawdownMode.Percentage, Day(1))

        for (i, v) in enumerate(vals)
            dt = DateTime(2025) + Day(i)
            collect_p(dt, v)
            collect_dd(dt, v)
        end

        svg = S.plot_equity_drawdown(p, dd; legend=true, output_format=:string)
        @test occursin("Max drawdown", svg) == has_drawdown
        @test !occursin(r"NaN|Inf", svg)
    end
end

@testitem "SVG open-order counts use integer ticks" begin
    using Fastback, Dates
    S = Fastback

    for vals in ([0], [0, 0], [0, 1], [3, 3], [0, 1_000_000])
        collect_counts, counts = periodic_collector(Int, Day(1))

        for (i, v) in enumerate(vals)
            collect_counts(DateTime(2025) + Day(i), v)
        end

        svg = S.plot_open_orders_count(counts; output_format=:string)
        ticks = [parse(Float64, replace(m.captures[1], "," => "")) for m in
            eachmatch(r"<text x=\"90\"[^>]*text-anchor=\"end\">([^<]+)</text>", svg)]
        @test length(ticks) >= 2
        @test first(ticks) == 0
        @test all(isinteger, ticks)
        vals == [0, 1] && @test ticks == [0, 1]
    end
end

@testitem "SVG trade returns and cashflows" begin
    using Fastback, Dates
    S = Fastback
    acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
    deposit!(acc, :USD, 10_000.0)
    @test_throws ArgumentError S.plot_cashflows(acc)
    @test_throws ArgumentError S.plot_realized_cum_returns_by_hour(acc.trades)
    inst = register_instrument!(acc, spot_instrument(Symbol("SVG/USD"), :SVG, :USD))
    dt = DateTime(2025)

    for (price, qty) in ((100.0, 2.0), (110.0, -1.0), (120.0, -1.0))
        fill_order!(acc, Order(oid!(acc), inst, dt, price, qty);
            dt, fill_price=price, bid=price, ask=price, last=price)
    end

    # Both closes share a timestamp: the notional-weighted return is 15%, not 32%.
    for (f, label) in ((S.plot_realized_cum_returns_by_hour, "0:00"),
        (S.plot_realized_cum_returns_by_weekday, "Wednesday"))
        options = S.Charts.ChartOptions(; title="Realized cumulative returns",
            left_y_axis=S.Charts.AxisOptions(; format=:percentage))
        # Axis bounds carry the last-digit rounding of the computed return.
        bounds = r" data-y-(lower|upper)=\"[^\"]*\""
        @test replace(f(acc.trades; xaxis_mode=:index, output_format=:string), bounds => "") ==
              replace(S.Charts.render_svg_line_chart([S.Charts.LineSeries(label, [1], [0.15])], options), bounds => "")
        @test_throws ArgumentError f(acc.trades; return_basis=:invalid)
    end

    push!(acc.cashflows, Cashflow(1, dt, CashflowKind.Funding, 1, -10.0, inst.index))
    push!(acc.cashflows, Cashflow(2, dt, CashflowKind.Other, 1, 5.0, inst.index))
    svg = S.plot_cashflows(acc; output_format=:string)
    @test occursin(">Funding<", svg)
    @test occursin(">Other<", svg)
    @test count("class=\"scatter-point\"", svg) == 2
end
