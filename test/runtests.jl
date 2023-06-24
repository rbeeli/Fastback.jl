using Test
using Dates
using Fastback

# To run a subset of tests, call Pkg.test as follows:
#
#   Pkg.test("Fastback", test_args=["utils.jl"])

requested_tests = lowercase.(ARGS)

if isempty(requested_tests)
    include("utils.jl")
    include("bidask.jl")
    include("position.jl")
    include("account.jl")
    include("collectors.jl")
    include("batch_backtest.jl")
else
    for test = requested_tests
        include(test)
    end
end
