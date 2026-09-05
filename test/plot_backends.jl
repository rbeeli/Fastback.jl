using TestItemRunner

@testitem "SVG works before Plots loads and remains the default after loading" begin
    # A fresh process verifies load order independently of other test items.
    script = raw"""
    using Fastback, Dates, Test
    @test plot_backend() === :svg
    @test svg_output_format() === :html
    @test Base.get_extension(Fastback, :FastbackPlotsExt) === nothing
    _, eq = periodic_collector(Float64, Day(1))
    @test Fastback.plot_equity(eq) isa Base.HTML
    err = try
        set_plot_backend!(:plots)
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("using Plots", sprint(showerror, err))
    @test plot_backend() === :svg
    @test_throws ArgumentError Fastback.plot_equity(eq; backend=:plots)
    using Plots
    @test Base.get_extension(Fastback, :FastbackPlotsExt) !== nothing
    @test all(id.name != "Query" for id in keys(Base.loaded_modules))
    @test plot_backend() === :svg
    @test Fastback.plot_equity(eq) isa Base.HTML
    @test Fastback.plot_equity(eq; backend=:plots) isa Plots.Plot
    """
    project = dirname(Base.active_project())
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$project -e $script`
    @test success(cmd)
end

@testitem "Unified plotting backend selection and overrides" begin
    ENV["GKSwstype"] = "100"
    using Fastback, Dates, Plots
    previous_backend = plot_backend()
    previous_output = svg_output_format()
    collect_eq, eq = periodic_collector(Float64, Day(1))
    collect_dd, dd = drawdown_collector(DrawdownMode.Percentage, Day(1))

    for (i, v) in enumerate([100.0, 50.0, 200.0, 140.0])
        dt = DateTime(2025) + Day(i)
        collect_eq(dt, v)
        collect_dd(dt, v)
    end

    acc = Account(; base_currency=CashSpec(:USD), broker=NoOpBroker())
    weights = fill(0.5, 4, 2)
    pv = PortfolioWeightsValues{DateTime,Day}(
        copy(dates(eq)), [:A, :B], [fill(0.5, 4), fill(0.5, 4)],
        Day(1), DateTime(0), dates(eq)[end])
    cases = (
        (Fastback.plot_title, ("Title",), (;)),
        (Fastback.plot_balance, (eq,), (;)),
        (Fastback.plot_equity, (eq,), (;)),
        (Fastback.plot_open_orders_count, (eq,), (;)),
        (Fastback.plot_drawdown, (dd,), (;)),
        (Fastback.plot_equity_drawdown, (eq, dd), (;)),
        (Fastback.plot_exposure, (), (; gross=eq, net=eq)),
        (Fastback.plot_portfolio_weights_over_time, (dates(eq), weights, [:A, :B]), (;)),
        (Fastback.plot_portfolio_weights_over_time, (pv,), (;)),
        (Fastback.plot_cashflows, (acc,), (;)),
        (Fastback.plot_realized_cum_returns_by_hour, (acc.trades,), (;)),
        (Fastback.plot_realized_cum_returns_by_weekday, (acc.trades,), (;)),
    )

    try
        set_svg_output_format!(:string)

        for backend in (:svg, :plots)
            @test set_plot_backend!(backend) === backend

            for (f, args, kwargs) in cases
                result = f(args...; kwargs...)
                @test backend === :svg ? result isa String : result isa Plots.Plot
            end

            @test Fastback.plot_equity(eq; backend=:svg) isa String
            @test Fastback.plot_equity(eq; backend=:plots) isa Plots.Plot
            @test plot_backend() === backend
        end

        @test_throws ArgumentError set_plot_backend!(:invalid)
        @test plot_backend() === :plots
        @test_throws ArgumentError Fastback.plot_equity(eq; backend=:invalid)
        set_svg_output_format!(:html)
        @test Fastback.plot_equity(eq) isa Plots.Plot
        @test Fastback.plot_equity(eq; backend=:svg) isa Base.HTML
        @test Fastback.plot_equity(eq; backend=:svg, output_format=:string) isa String

        for name in (:balance, :equity, :open_orders_count, :drawdown, :equity_drawdown, :exposure)
            f = getfield(Fastback, Symbol(:plot_, name, :!))
            args = name === :drawdown ? (dd,) : name === :equity_drawdown ? (eq, dd) :
                name === :exposure ? () : (eq,)
            kwargs = name === :exposure ? (; gross=eq) : (;)
            io = IOBuffer()
            @test f(io, args...; backend=:svg, kwargs...) === io
            @test startswith(String(take!(io)), "<svg")
            plt = Plots.plot()
            @test f(plt, args...; kwargs...) === plt
            @test_throws ArgumentError f(io, args...; backend=:plots, kwargs...)
            @test_throws ArgumentError f(plt, args...; backend=:svg, kwargs...)
        end

        @test_throws ArgumentError Fastback.plot_title!(Plots.plot(), "Title")
    finally
        set_plot_backend!(previous_backend)
        set_svg_output_format!(previous_output)
    end
end
