using Base.Threads
using Dates
using Printf


function batch_backtest(params_list::Vector{Dict{Any, Any}}, backtest_func::Function)::Vector{Account}
    n_params = length(params_list)
    n_threads = nthreads()

    println("----------------------------------------------------------------")
    println("Batch backtest")
    println(" > Threads:     $n_threads")
    println(" > Iterations:  $n_params")
    println("")

    results = Vector{Account}(undef, n_params)
    n_done = 0
    last_info = 0.0
    locker = SpinLock()

    @time begin
        # for i = 1:n_params
        @threads for i = 1:n_params
            # get params used for backtest
            prms = params_list[i]

            # run backtest
            acc = backtest_func(; prms...)

            # progress info
            lock(locker)
            n_done += 1
            if time() - last_info > 1.0 || n_done == n_params
                println(" $(@sprintf("%.1f", 100*(n_done/n_params)))% ($n_done/$n_params)")
                last_info = time()
            end
            unlock(locker)

            println(
                "\n"*
                "\n  $i:  # trades:           $(length(acc.closed_positions))"*
                "\n  $i:  nominal return:     $(sum(map(x -> calc_nominal_return_net(x), acc.closed_positions)))"*
                "\n")

            results[i] = acc
        end
    end

    println("----------------------------------------------------------------")

    results
end
