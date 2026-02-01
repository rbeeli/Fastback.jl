using Base.Threads
using Dates
using Printf

"""
Run a batch of backtests over a parameter list, optionally in parallel.
"""
function batch_backtest(
    backtest_return_type::Type{TReturn},
    params_list,
    backtest_func
    ;
    finished_func=nothing,
    progress_log_interval::Int=1,
    gc_interval::Int=-1,
    gc_full::Bool=true,
    parallel::Bool=true
)::Vector{TReturn} where {TReturn}
    n_threads = parallel ? Threads.nthreads() : 1
    n_params = length(params_list)

    display_width = displaysize(stdout)[2]
    printstyled("━"^display_width * "\n"; color=:green)
    printstyled("Batch backtest [iters=$n_params, threads=$n_threads]\n"; color=:green)

    results = Vector{backtest_return_type}(undef, n_params)
    n_done = 0
    start_time = now()
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
            if progress_log_interval > 0 && (n_done % progress_log_interval == 0 || n_done == n_params)
                # ETA string
                elapsed = now() - start_time
                eta = compute_eta(elapsed, n_done / n_params)
                eta_str = format_period_HHMMSS(eta)

                # progress
                prog_pct = @sprintf("%3.0d", floor(Int, 100 * (n_done / n_params)))
                num_digits = floor(Int, log10(n_params)) + 1
                prog_int = lpad(n_done, num_digits)

                printstyled("$prog_pct%  [$(prog_int)∕$(n_params)]  ETA $eta_str \n"; color=:green)
            end

            if gc_interval > 0 && (n_done % gc_interval == 0 || n_done == n_params)
                # run garbage collection
                GC.gc(gc_full)
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

    printstyled("━"^display_width * "\n"; color=:green)

    results
end
