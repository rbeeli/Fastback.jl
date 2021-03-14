function value_collector(period::Period)::Tuple{Function, PeriodicValues}
    pv = Base.RefValue(PeriodicValues(period))

    function collector(dt::DateTime, value::Float64)
        if (dt - pv[].last_dt) >= period
            push!(pv[].values, (dt, value))
            pv[].last_dt = dt
        end
    end

    return collector, pv[]
end


# function value_collector(period::Period, round_func::Function)::Tuple{Function, PeriodicValues}
#     pv = Base.RefValue(PeriodicValues(period))

#     function collector(dt::DateTime, value::Float64)
#         dt_rounded = round_func(dt)
#         if (dt_rounded - pv[].last_dt) >= period
#             push!(pv[].values, (dt_rounded, value))
#             pv[].last_dt = dt_rounded
#         end
#     end

#     return collector, pv[]
# end


function max_value_collector(period::Period)::Tuple{Function, PeriodicValues}
    pv = Base.RefValue(PeriodicValues(period))

    function collector(dt::DateTime, value::Float64)
        if isnan(pv[].last_value)
            # initialize max value
            pv[].last_value = value
        end

        # update max value
        pv[].last_value = max(pv[].last_value, value)

        if (dt - pv[].last_dt) >= period
            # collect value
            push!(pv[].values, (dt, pv[].last_value))
            pv[].last_dt = dt

            # reset
            pv[].last_value = value
        end
    end

    return collector, pv[]
end


function drawdown_collector(period::Period)::Tuple{Function, PeriodicValues}
    pv = Base.RefValue(PeriodicValues(period))

    function collector(dt::DateTime, equity::Float64)
        if isnan(pv[].last_value)
            # initialize max equity value
            pv[].last_value = equity
        end

        # update max equity value
        pv[].last_value = max(pv[].last_value, equity)

        if (dt - pv[].last_dt) >= period
            drawdown = min(0, equity - pv[].last_value)
            push!(pv[].values, (dt, drawdown))
            pv[].last_dt = dt
        end

        return
    end

    return collector, pv[]
end
