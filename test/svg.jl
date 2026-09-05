using TestItemRunner

@testitem "SVG exposure legend is horizontally centered" begin
    using Fastback, Dates
    collect_eq, eq = periodic_collector(Float64, Day(1))
    collect_eq(DateTime(2025), 100.0)

    for width in (320, 800, 1200)
        svg = Fastback.plot_exposure(; gross=eq, net=eq, long=eq, short=eq, width, output_format=:string)
        rows = collect(eachmatch(r"<text x=\"([^\"]+)\"[^>]*text-anchor=\"middle\"[^>]*><tspan", svg))
        @test !isempty(rows)
        @test all(m -> parse(Float64, m.captures[1]) == width / 2, rows)

        for label in ("Gross", "Net", "Long", "Short")
            @test count(">$label</tspan>", svg) == 1
        end
    end

    @test !occursin("<tspan", Fastback.plot_exposure(; gross=eq, legend=false, output_format=:string))
    @test !occursin("<tspan", Fastback.plot_exposure(; output_format=:string))
end

@testitem "SVG end labels follow each series endpoint" begin
    using Fastback
    series = [
        Fastback._svg_series([1.0, 2.0], [0.1, 0.2]; label="First", color="#123456", style=:line),
        Fastback._svg_series([1.0, 3.0, 4.0], [0.2, 0.3, NaN]; label="Second", color="#654321", style=:line),
        Fastback._svg_series(Float64[], Float64[]; label="Empty"),
    ]
    svg = sprint(io -> Fastback._svg_chart(io, series; legend=false, end_labels=true))
    labels = collect(eachmatch(r"<text x=\"([^\"]+)\" y=\"([^\"]+)\"[^>]*fill=\"(#[0-9a-f]+)\"[^>]*>(First|Second)</text>", svg))
    @test length(labels) == 2
    @test parse(Float64, labels[1].captures[1]) < parse(Float64, labels[2].captures[1])
    @test parse(Float64, labels[1].captures[2]) > parse(Float64, labels[2].captures[2])
    @test [m.captures[3] for m in labels] == ["#123456", "#654321"]
    @test !occursin(">Empty</text>", svg)
    @test !occursin(r"NaN|Inf", svg)
end

@testitem "SVG redundant legends are hidden by default" begin
    using Fastback, Dates
    collect_eq, eq = periodic_collector(Float64, Day(1))
    collect_dd, dd = drawdown_collector(DrawdownMode.Percentage, Day(1))

    for (i, value) in enumerate([100.0, 80.0])
        collect_eq(DateTime(2025) + Day(i), value)
        collect_dd(DateTime(2025) + Day(i), value)
    end

    for (render, args) in (
        (Fastback.plot_balance, (eq,)),
        (Fastback.plot_equity, (eq,)),
        (Fastback.plot_open_orders_count, (eq,)),
        (Fastback.plot_drawdown, (dd,)),
        (Fastback.plot_equity_drawdown, (eq, dd)),
    )
        svg = render(args...; output_format=:string)
        @test svg == render(args...; legend=false, output_format=:string)
        @test !occursin(r"<text[^>]* y=\"52(?:\.0)?\"", svg)
        @test occursin(r"<text[^>]* y=\"52(?:\.0)?\"", render(args...; legend=true, output_format=:string))
    end

    exposure = Fastback.plot_exposure(; gross=eq, net=eq, output_format=:string)
    @test occursin(">Gross</tspan>", exposure)
    @test occursin(">Net</tspan>", exposure)
end

@testitem "SVG y-axis ticks use decimal notation" begin
    using Fastback, Dates
    @test Fastback._svg_decimal(1_000_000.0) == "1000000"
    @test Fastback._svg_decimal(10_000.25) == "10000.25"
    @test Fastback._svg_decimal(-12_345.5) == "-12345.5"
    @test Fastback._svg_decimal(1e-7) == "0.0000001"
    @test Fastback._svg_decimal(-0.0) == "0"
    collect_eq, eq = periodic_collector(Float64, Day(1))
    collect_dd, dd = drawdown_collector(DrawdownMode.Percentage, Day(1))

    for (i, value) in enumerate([1_000_000.0, 900_000.0])
        collect_eq(DateTime(2025) + Day(i), value)
        collect_dd(DateTime(2025) + Day(i), value)
    end

    plots = (
        Fastback.plot_balance(eq; output_format=:string),
        Fastback.plot_equity(eq; output_format=:string),
        Fastback.plot_exposure(; gross=eq, output_format=:string),
        Fastback.plot_equity_drawdown(eq, dd; output_format=:string),
    )

    for svg in plots
        ticks = [m.captures[1] for m in eachmatch(
            r"<text[^>]*text-anchor=\"end\"[^>]*>([-+0-9.eE]+)</text>", svg)]
        @test length(ticks) == 5
        @test all(t -> !occursin(r"[eE]", t), ticks)
        @test maximum(parse.(Float64, ticks)) >= 1_000_000
    end
end

@testitem "SVG global output format" begin
    using Fastback, Dates
    S = Fastback
    previous = S.svg_output_format()
    try
        @test S.set_svg_output_format!(:string) === :string
        raw = S.plot_title("Output format")
        @test raw isa String
        @test S.set_svg_output_format!(:html) === :html
        @test S.svg_output_format() === :html
        html = S.plot_title("Output format")
        @test html isa Base.HTML
        @test repr(MIME"text/html"(), html) == raw
        @test S.plot_title("Output format"; output_format=:string) == raw
        @test S.svg_output_format() === :html
        _, eq = periodic_collector(Float64, Day(1))
        @test S.plot_equity(eq) isa Base.HTML
        io = IOBuffer()
        @test S.plot_title!(io, "Output format") === io
        @test String(take!(io)) == raw
        @test_throws ArgumentError S.set_svg_output_format!(:invalid)
        @test S.svg_output_format() === :html
        @test_throws ArgumentError S.plot_title("Output format"; output_format=:invalid)
        S.set_svg_output_format!(:string)
        @test S.plot_title("Output format") isa String
        @test S.plot_title("Output format"; output_format=:html) isa Base.HTML
    finally
        S.set_svg_output_format!(previous)
    end
end

@testitem "SVG strings and direct IO rendering" begin
    using Fastback, Dates
    S = Fastback
    previous_output = S.svg_output_format()
    S.set_svg_output_format!(:string)
    try
        collect_eq, eq = periodic_collector(Float64, Day(1))
        collect_dd, dd = drawdown_collector(DrawdownMode.Percentage, Day(1))

        for (i, v) in enumerate([100.0, 120.0, 90.0, 110.0])
            dt = DateTime(2025) + Day(i)
            collect_eq(dt, v)
            collect_dd(dt, v)
        end

        for name in (:balance, :equity, :open_orders_count, :drawdown, :equity_drawdown,
            :exposure, :portfolio_weights_over_time, :title)
            args = name === :drawdown ? (dd,) : name === :equity_drawdown ? (eq, dd) :
                name === :exposure ? () : name === :title ? ("<Title & \"quote\">",) :
                name === :portfolio_weights_over_time ? (dates(eq), fill(0.5, 4, 2), ["A", "B"]) : (eq,)
            kwargs = name === :exposure ? (; gross=eq, net=eq) : (;)
            svg = getfield(S, Symbol(:plot_, name))(args...; kwargs...)
            io = IOBuffer()
            @test getfield(S, Symbol(:plot_, name, :!))(io, args...; kwargs...) === io
            @test String(take!(io)) == svg
            @test startswith(svg, "<svg xmlns=")
            @test endswith(strip(svg), "</svg>")
            @test occursin("#182235", svg)
            @test !occursin(r"NaN|Inf", svg)
        end

        @test occursin("&lt;Title &amp; &quot;quote&quot;&gt;", S.plot_title("<Title & \"quote\">"))
        @test !occursin("<path", S.plot_title("Title only"))
        @test occursin("Max drawdown", S.plot_equity_drawdown(eq, dd; legend=true))
        @test !occursin("Max drawdown", S.plot_equity_drawdown(eq, dd; legend=true, show_max_dd=false))
        @test occursin("%", S.plot_drawdown(dd))
        @test !occursin("2025-", S.plot_equity(eq; xaxis_mode=:index))
        @test_throws ArgumentError S.plot_equity(eq; xaxis_mode=:invalid)
        @test_throws ArgumentError S.plot_equity(eq; width=0)
        @test_throws ArgumentError S.plot_equity(eq; ylims=(1, 1))
        @test_throws ArgumentError S.plot_portfolio_weights_over_time(dates(eq), ones(3, 2), ["A", "B"])
        @test_throws ArgumentError S.plot_portfolio_weights_over_time(dates(eq), fill(NaN, 4, 2), ["A", "B"])

        _, empty = periodic_collector(Float64, Day(1))
        @test occursin("<svg", S.plot_equity(empty))

        for vals in ([0.0], [3.0, 3.0], [NaN, Inf], [1.0, NaN, 2.0])
            collect_p, p = periodic_collector(Float64, Day(1))

            for (i, v) in enumerate(vals)
                collect_p(DateTime(2025) + Day(i), v)
            end

            svg = S.plot_equity(p)
            @test !occursin(r"NaN|Inf", svg)
            isequal(vals, [1.0, NaN, 2.0]) && @test count("<circle", svg) == 2
        end

        @test !isdefined(Fastback, :plot_violin_realized_returns_by_day)
        @test !isdefined(Fastback, :plot_violin_realized_returns_by_hour)
    finally
        S.set_svg_output_format!(previous_output)
    end
end

@testitem "SVG drawdown markers respect the drawdown mode" begin
    using Fastback, Dates
    S = Fastback
    collect_eq, eq = periodic_collector(Float64, Day(1))

    for (i, v) in enumerate([100.0, 50.0, 200.0, 140.0])
        collect_eq(DateTime(2025) + Day(i), v)
    end

    marker_x = Dict{DrawdownMode.T,Vector{Float64}}()

    for mode in (DrawdownMode.Percentage, DrawdownMode.PnL)
        collect_dd, dd = drawdown_collector(mode, Day(1))

        for (dt, v) in zip(dates(eq), values(eq))
            collect_dd(dt, v)
        end

        svg = S.plot_equity_drawdown(eq, dd; xaxis_mode=:index, output_format=:string)
        xs = [parse(Float64, m.captures[1]) for m in eachmatch(r"<circle cx=\"([^\"]+)\"", svg)]
        @test length(xs) == 2
        marker_x[mode] = xs
        @test !occursin("<circle", S.plot_equity_drawdown(eq, dd; show_max_dd=false, output_format=:string))
    end

    # The 50% decline occurs before the larger absolute loss of 60.
    @test marker_x[DrawdownMode.Percentage][1] < marker_x[DrawdownMode.Percentage][2] <
        marker_x[DrawdownMode.PnL][1] < marker_x[DrawdownMode.PnL][2]

    for (vals, has_drawdown) in (([0.0, 0.0], false), ([100.0, 110.0], false), ([100.0, NaN, 50.0], true))
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

@testitem "SVG open-order counts use bounded integer ticks" begin
    using Fastback, Dates
    S = Fastback

    for vals in (Int[], [0], [0, 0], [0, 1], [3, 3], [0, 1_000_000])
        collect_counts, counts = periodic_collector(Int, Day(1))

        for (i, v) in enumerate(vals)
            collect_counts(DateTime(2025) + Day(i), v)
        end

        svg = S.plot_open_orders_count(counts; output_format=:string)
        ticks = [parse(Float64, m.captures[1]) for m in
            eachmatch(r"text-anchor=\"end\"[^>]*>([^<]+)</text>", svg)]
        @test 2 <= length(ticks) <= 5
        @test first(ticks) == 0
        @test all(isinteger, ticks)
        @test issorted(ticks)
        @test !occursin(r"NaN|Inf", svg)
        vals == [0, 1] && @test ticks == [0, 1]
    end
end

@testitem "SVG trade returns and cashflows" begin
    using Fastback, Dates
    S = Fastback
    previous_output = S.svg_output_format()
    S.set_svg_output_format!(:string)
    try
        acc = Account(; funding=AccountFunding.Margined, base_currency=CashSpec(:USD), broker=NoOpBroker())
        deposit!(acc, :USD, 10_000.0)
        @test occursin("No cashflow data", S.plot_cashflows(acc))
        @test occursin("<svg", S.plot_realized_cum_returns_by_hour(acc.trades))
        inst = register_instrument!(acc, spot_instrument(Symbol("SVG/USD"), :SVG, :USD))
        dt = DateTime(2025)

        for (price, qty) in ((100.0, 2.0), (110.0, -1.0), (120.0, -1.0))
            fill_order!(acc, Order(oid!(acc), inst, dt, price, qty);
                dt, fill_price=price, bid=price, ask=price, last=price)
        end

        # Both closes share a timestamp: notional-weighted return is 15%, not 32%.

        for (f, label) in ((S.plot_realized_cum_returns_by_hour, "0:00"),
            (S.plot_realized_cum_returns_by_weekday, "Wednesday"))
            svg = f(acc.trades)
            @test occursin("<g class=\"series-end-labels\">", svg)
            @test count(">$label</text>", svg) == 1
            @test !occursin(r"<text[^>]* y=\"52(?:\.0)?\"", svg)
            @test !occursin(">$label</text>", f(acc.trades; end_labels=false))
            @test occursin(">15%</text>", svg)
            @test !occursin("32%", svg)
            @test occursin(">15%</text>", f(acc.trades; return_basis=:net, xaxis_mode=:index))
            @test_throws ArgumentError f(acc.trades; return_basis=:invalid)
        end

        push!(acc.cashflows, Cashflow(1, dt, CashflowKind.Funding, 1, -10.0, inst.index))
        push!(acc.cashflows, Cashflow(2, dt, CashflowKind.Other, 1, 5.0, inst.index))
        svg = S.plot_cashflows(acc)
        @test occursin("Funding", svg)
        @test occursin("Other", svg)
        @test count("translate", svg) == 2
    finally
        S.set_svg_output_format!(previous_output)
    end
end
