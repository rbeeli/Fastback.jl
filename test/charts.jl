using TestItemRunner

@testitem "charts render number text and line documents" begin
    using Test, Fastback, Dates
    using Fastback.Charts

    @test Charts._display(100.0) == "100"
    @test Charts._display(1.0e-5) == "0.00001"
    @test Charts._display(3.5071599964010813e6) == "3507159.9964010813"
    @test Charts._display(-0.0) == "-0"
    @test Charts._debug(1.0) == "1.0"
    @test Charts.number_label(1_234_567.0) == "1.235e6"
    @test Charts.number_label(0.000125) == "1.250e-4"
    @test Charts.number_label(12.5) == "12.5"
    @test Charts.number_label(1_500.0) == "1500"

    times = [DateTime(2030, 1, 1) + Day(day) for day in 0:3]
    svg = render_svg_line_chart([LineSeries("level", times, [1.0, NaN, 3.0, 4.0]),
            LineSeries("drawdown", times, [0.0, -0.1, -0.2, 0.0]; axis=:right)],
        ChartOptions(; title="A & B", right_y_axis=AxisOptions(; format=:percentage)))
    @test startswith(svg, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg ")
    @test occursin("data-chart-type=\"line\"", svg)
    @test occursin("data-y-right-scale=\"linear\"", svg)
    @test occursin("<title>A &amp; B</title>", svg)
    @test occursin("class=\"line-point\"", svg)
    @test endswith(svg, "</g></g></svg>\n")
end

@testitem "charts reject invalid data and options" begin
    using Test, Fastback, Dates
    using Fastback.Charts

    times = [DateTime(2030, 1, 1), DateTime(2030, 1, 2)]
    @test_throws ArgumentError render_svg_line_chart([LineSeries("x", times, [1.0])], ChartOptions())
    @test_throws ArgumentError render_svg_line_chart([LineSeries("x", times, [1.0, 2.0]; axis=:right)], ChartOptions())
    @test_throws ArgumentError render_svg_line_chart([LineSeries("x", times, [-1.0, 2.0])],
        ChartOptions(; left_y_axis=AxisOptions(; scale=:logarithmic)))
    @test_throws ArgumentError render_svg_line_chart([LineSeries("x", [1.0, 2.0], [1.0, 2.0])],
        ChartOptions(; x_date_format="%Y"))
    @test_throws ArgumentError render_svg_bar_chart(["a"], [BarSeries("x", [1.0])], BarChartOptions(; bar_width=1.5))
    @test_throws ArgumentError render_svg_stacked_bar_chart(times, [StackedBarSeries("x", [1.0, 2.0])], ChartOptions())
    @test_throws ArgumentError write_svg_line_chart(joinpath(mktempdir(), "chart.png"),
        [LineSeries("x", times, [1.0, 2.0])], ChartOptions())
end

@testitem "charts write files atomically with year ticks over long spans" begin
    using Test, Fastback, Dates
    using Fastback.Charts

    times = [DateTime(2010, 1, 1) + Day(30 * index) for index in 0:120]
    path = joinpath(mktempdir(), "nested", "chart.svg")
    write_svg_line_chart(path, [LineSeries("level", times, collect(1.0:121.0))], ChartOptions(; legend=nothing))
    svg = read(path, String)
    @test occursin(">2010</text>", svg)
    @test !occursin("<rect x=\"40\"", svg)
    @test !isfile(path * ".tmp")
end
