# To run a subset of tests, call Pkg.test as follows:
#
# import Pkg; Pkg.test("Fastback", test_args=["utils.jl"])
# import Pkg; Pkg.test("Fastback", test_args=["account.jl"])
# import Pkg; Pkg.test("Fastback", test_args=["print.jl"])

requested_tests = lowercase.(ARGS)

if isempty(requested_tests)
    include("utils.jl")
    include("collectors.jl")
    include("batch_backtest.jl")
    include("position.jl")
    include("account.jl")
    include("print.jl")
else
    for test = requested_tests
        include(test)
    end
end
