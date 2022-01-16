using Base.Threads
using Dates
using Printf


function batch_backtest(
    params_list::Vector{Dict{Any, Any}},
    backtest_func::Function;
    finished_func::Union{Function, Nothing}=nothing,
    n_threads::Int64=-1)::Vector{Union{Account, Nothing}}

    if n_threads == -1
        # use all available CPU cores
        n_threads = nthreads()
    end

    n_params = length(params_list)

    printstyled("─"^80*"\n"; color=:green)
    printstyled("Batch backtest [threads=$n_threads, itrs=$n_params]\n"; color=:green)
    println("")

    results = Vector{Union{Account, Nothing}}(nothing, n_params)
    n_done = 0
    last_info = 0.0
    lk = SpinLock()

    @time begin
        # for i = 1:n_params
        @threads for i = 1:n_params
            # get params used for backtest
            params = params_list[i]

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

        println("")
    end

    printstyled("─"^80*"\n"; color=:green)

    results
end
