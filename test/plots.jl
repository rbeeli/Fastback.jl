using TestItemRunner

@testitem "Plot backends share their color theme" begin
    ENV["GKSwstype"] = "100"
    using Fastback, Dates, Plots
    colors = Fastback._PLOT_COLORS
    previous_backend = plot_backend()
    previous_background = Plots.default(:background_color)
    collect_eq, eq = periodic_collector(Float64, Day(1))
    collect_dd, dd = drawdown_collector(DrawdownMode.Percentage, Day(1))

    for (i, value) in enumerate([100.0, 80.0])
        collect_eq(DateTime(2025) + Day(i), value)
        collect_dd(DateTime(2025) + Day(i), value)
    end

    try
        for (render, data, color) in (
            (Fastback.plot_balance, eq, colors.balance),
            (Fastback.plot_equity, eq, colors.equity),
            (Fastback.plot_open_orders_count, eq, colors.open_orders),
            (Fastback.plot_drawdown, dd, colors.drawdown),
        )
            set_plot_backend!(:svg)
            svg = render(data; output_format=:string)
            @test occursin("stroke=\"$color\"", svg)
            @test occursin("fill=\"$(colors.canvas)\"", svg)
            set_plot_backend!(:plots)
            plt = render(data)
            @test plt.series_list[1][:linecolor] == Plots.plot_color(color)
            @test plt[1][:background_color_subplot] == Plots.plot_color(colors.canvas)
            @test plt[1][:xaxis][:foreground_color_axis] == Plots.plot_color(colors.axis)
        end

        exposure = Fastback.plot_exposure(; gross=eq, net=eq, long=eq, short=eq)
        expected = (colors.exposure_gross, colors.exposure_net, colors.exposure_long, colors.exposure_short)
        @test [s[:linecolor] for s in exposure.series_list] == collect(Plots.plot_color.(expected))
        weights = Fastback.plot_portfolio_weights_over_time(dates(eq), [0.4 0.6; 0.5 0.5], [:A, :B])
        @test weights.series_list[1][:seriescolor] == Plots.plot_color(Fastback._PLOT_PALETTE[1])
        @test weights.series_list[2][:seriescolor] == Plots.plot_color(Fastback._PLOT_PALETTE[2])
        custom = Fastback.plot_equity(eq; linecolor=:red, background_color=:white)
        @test custom.series_list[1][:linecolor] == Plots.plot_color(:red)
        @test custom[1][:background_color_subplot] == Plots.plot_color(:white)
        @test Plots.default(:background_color) == previous_background
    finally
        set_plot_backend!(previous_backend)
    end
end

@testitem "Plots drawdown markers respect the drawdown mode" begin
    ENV["GKSwstype"] = "100"
    using Fastback, Dates, Plots
    previous_backend = plot_backend()
    set_plot_backend!(:plots)
    try
        collect_eq, eq = periodic_collector(Float64, Day(1))

        for (i, v) in enumerate([100.0, 50.0, 200.0, 140.0])
            collect_eq(DateTime(2025) + Day(i), v)
        end

        for (mode, expected) in ((DrawdownMode.Percentage, [100.0, 50.0, -0.5]),
            (DrawdownMode.PnL, [200.0, 140.0, -60.0]))
            collect_dd, dd = drawdown_collector(mode, Day(1))

            for (dt, v) in zip(dates(eq), values(eq))
                collect_dd(dt, v)
            end

            plt = Fastback.plot_equity_drawdown(eq, dd)
            markers = filter(s -> s[:seriestype] === :scatter, plt.series_list)
            @test [only(s[:y]) for s in markers] ≈ expected
            @test markers[end][:label] == "Max drawdown"
            @test !isempty(repr(MIME"image/svg+xml"(), plt))

            overlay = Plots.plot()
            @test Fastback.plot_equity_drawdown!(overlay, eq, dd) === overlay
            overlay_markers = filter(s -> s[:seriestype] === :scatter, overlay.series_list)
            @test [only(s[:y]) for s in overlay_markers] ≈ expected

            unmarked = Fastback.plot_equity_drawdown(eq, dd; show_max_dd=false)
            @test all(s -> s[:seriestype] !== :scatter, unmarked.series_list)
        end

        # Shared selection also skips missing observations and handles a zero peak.
        @test Fastback._plot_max_drawdown_indices([NaN, 100.0, 50.0], DrawdownMode.Percentage) == (2, 3, -0.5)
        @test Fastback._plot_max_drawdown_indices([0.0, 0.0], DrawdownMode.Percentage) == (0, 0, 0.0)
    finally
        set_plot_backend!(previous_backend)
    end
end

@testitem "Plots open-order counts use bounded integer ticks" begin
    ENV["GKSwstype"] = "100"
    using Fastback, Dates, Plots
    previous_backend = plot_backend()
    set_plot_backend!(:plots)
    try

        for vals in (Int[], [0], [0, 0], [0, 1], [3, 3], [0, 1_000_000])
            collect_counts, counts = periodic_collector(Int, Day(1))

            for (i, v) in enumerate(vals)
                collect_counts(DateTime(2025) + Day(i), v)
            end

            plt = Fastback.plot_open_orders_count(counts)
            ticks, labels = only(Plots.yticks(plt))
            @test 2 <= length(ticks) <= 5
            @test first(ticks) == 0
            @test all(isinteger, ticks)
            @test parse.(Float64, labels) == collect(ticks)
            @test Plots.ylims(plt) == (0.0, max(1.0, maximum(vals; init=0)))
            @test !isempty(repr(MIME"image/svg+xml"(), plt))

            overlay = Plots.plot()
            @test Fastback.plot_open_orders_count!(overlay, counts) === overlay
            @test Plots.ylims(overlay) == Plots.ylims(plt)
            @test Plots.yticks(overlay) == Plots.yticks(plt)
        end

        _, empty = periodic_collector(Int, Day(1))
        @test Plots.ylims(Fastback.plot_open_orders_count(empty; ylims=(0, 10))) == (0.0, 10.0)
        @test_throws ArgumentError Fastback.plot_open_orders_count(empty; ylims=(1, 1))
    finally
        set_plot_backend!(previous_backend)
    end
end
