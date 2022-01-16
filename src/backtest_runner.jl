using Base.Threads
using Dates
using Printf


function batch_backtest(
    params_list::Vector{Dict{Any, Any}},
    backtest_func::Function;
    finished_func::Union{Function, Nothing}=nothing,
    parallel::Bool=true)::Vector{Union{Account, Nothing}}

    n_threads = !parallel ? Threads.nthreads() : 1
    n_params = length(params_list)

    printstyled("─"^80*"\n"; color=:green)
    printstyled("Batch backtest [threads=$n_threads, itrs=$n_params]\n"; color=:green)
    println("")

    results = Vector{Union{Account, Nothing}}(nothing, n_params)
    n_done = 0
    last_info = 0.0
    lk = SpinLock()

    function single_pass(params, i)
        # run backtest
        acc = backtest_func(; params...)

        lock(lk)
        try
            n_done += 1

            if acc isa Account
                results[i] = acc

                # callback for single finished backtest if set
                if !isnothing(finished_func)
                    finished_func(params, acc)
                end
            else
                printstyled(
                    "WARN [Fastback] backtest_runner - No Account instance returned from backtest_func, but of type "*string(typeof(acc))*". finished_func will not be called.\n"; color=:yellow);
            end

            # print progress
            if time() - last_info > 1.0 || n_done == n_params
                printstyled("\n$(@sprintf("%3.0d", 100*(n_done/n_params)))%\t$n_done/$n_params\n"; color=:green)
                last_info = time()
            end
        finally
            unlock(lk)
        end
    end

    @time begin
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
    end

    println("")
    printstyled("─"^80*"\n"; color=:green)

    results
end
