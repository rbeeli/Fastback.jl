using Base.Threads
using Dates
using Printf


function batch_backtest(
    backtest_return_type        ::Type{T},
    params_list                 ::Vector{Dict{Any, Any}},
    backtest_func               ::Function;
    finished_func               ::Union{Function, Nothing}=nothing,
    progress_log_interval       ::Int=1,
    parallel                    ::Bool=true
)::Vector{T} where T

    n_threads = parallel ? Threads.nthreads() : 1
    n_params = length(params_list)

    printstyled("─"^80*"\n"; color=:green)
    printstyled("Batch backtest [iterations=$n_params, threads=$n_threads]\n"; color=:green)

    results = Vector{backtest_return_type}(undef, n_params)
    n_done = 0
    lk = SpinLock()

    function single_pass(params, i)
        # run backtest
        backtest_res = backtest_func(; params...)

        lock(lk)
        try
            n_done += 1
            results[i] = backtest_res

            # callback for single finished backtest if set
            if !isnothing(finished_func)
                try
                    finished_func(params, backtest_res)
                catch e
                    printstyled("!!! Error in finished_func: $e\n"; color=:red)
                end
            end

            # print progress
            if progress_log_interval > 0 && (n % progress_log_interval == 0 || n_done == n_params)
                printstyled("> $(@sprintf("%3.0d", 100*(n_done/n_params)))% [$n_done/$n_params]\n"; color=:green)
            end
        finally
            unlock(lk)
        end
    end

    if parallel
        # multi-threaded execution
        @threads for i = 1:n_params
            single_pass(params_list[i], i)
        end
    else
        # single-threaded execution
        for i = 1:n_params
            single_pass(params_list[i], i)
        end
    end

    printstyled("─"^80*"\n"; color=:green)

    results
end
