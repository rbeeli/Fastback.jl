# Run with `julia --project=benchmark test/manual/perf_backtesting.jl`.
# The maintained runtime/scaling suite lives in benchmark/; see its README.
include(joinpath(@__DIR__, "..", "..", "benchmark", "benchmarks.jl"))
