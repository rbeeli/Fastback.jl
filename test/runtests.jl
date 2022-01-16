module FastbackTests

using Test
using Dates
using Fastback

# To run a subset of tests, call Pkg.test as follows:
#
#   Pkg.test("Fastback", test_args=["permute.jl"])

requested_tests = lowercase.(ARGS)

if isempty(requested_tests)
    include("utils.jl")
    include("bidask.jl")
    include("position.jl")
    include("account.jl")
    include("collectors.jl")
    include("batch_backtest.jl")
    include("perf_collectors.jl")
    include("perf_backtesting.jl")
else
    for test_name=requested_tests
        include(test_name)
    end
end

end
