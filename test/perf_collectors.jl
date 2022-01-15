using BenchmarkTools
using Dates
using Fastback


# synthetic data
const N = 10_000_000;
const prices = 1000.0 .+ 100cumsum(randn(N) .+ 0.01);
const dts = map(x -> DateTime(2000, 1, 1) + Minute(x) + Millisecond(123), 1:N);


# periodic_collector
function run_test1(dts::Vector{DateTime}, values::Vector{Float64})
    f, collected = periodic_collector(Float64, Minute(10))

    for i in 1:length(dts)
        @inbounds f(dts[i], values[i])
    end

    collected
end

# predicate_collector
function run_test2(dts::Vector{DateTime}, values::Vector{Float64})
    predicate = (collected, dt, value) -> (dt - collected.last_dt) >= Minute(10)
    f, collected = predicate_collector(Float64, predicate, 0.0)

    for i in 1:length(dts)
        @inbounds f(dts[i], values[i])
    end

    collected
end

# func_collector
function run_test_func(dts::Vector{DateTime}, values::Vector{Float64})
    # when should we collect a new value?
    # what is the new value?
    @inline function func(collected, dt, value)
        do_collect = (dt - collected.last_dt) >= Minute(10)
        do_collect, value
    end

    # create collector
    collect, collected = func_collector(func, DateTime(0), 0.0)

    for i in 1:length(dts)
        @inbounds collect(dts[i], values[i])
    end

    collected
end


collected1 = run_test1(dts, prices);
collected2 = run_test2(dts, prices);

@test all(collected1.values .== collected2.values);

@benchmark run_test1(dts, prices) samples=40 evals=2
@benchmark run_test2(dts, prices) samples=40 evals=2
