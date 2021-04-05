using Statistics
using Distributions

# https://oxfordstrat.com/coasdfASD32/uploads/2016/03/How-Sharp-Is-the-Sharpe-Ratio.pdf



"""
    skewness(x; method=:moment)

Calculates the skewness using on the specified method.

# Methods
- Moment (default)
- Fisher-Pearson
- Sample

# Arguments
- `x`:          Vector of values.
- `method`:     Estimation method: `:moment`, `:fisher_pearson` or `:sample`.
"""
function skewness(x; method::Symbol=:moment)
    n = length(x)
    mean_devs = x .- mean(x)

    if method == :moment
        # Moment
        return mean(mean_devs.^3) / sqrt(mean(mean_devs.^2))^3  # sqrt(x)^3 faster than x^1.5 !
    elseif method == :fisher_pearson
        # Fisher-Pearson
        if n > 2
            return sqrt(n*(n-1))/(n-2) * mean(mean_devs.^3) / sqrt(mean(mean_devs.^2))^3  # sqrt(x)^3 faster than x^1.5 !
        else
            return NaN
        end
    elseif method == :sample
        # Sample
        return n/((n-1)*(n-2)) * sum(mean_devs.^3 / sqrt(mean(mean_devs.^2))^3)
    end

    throw(ArgumentError("Passed method parameter '$(method)' is invalid, must be one of :moment, :fisher_pearson, :sample."))
end



"""
    kurtosis(x; method=:excess)

Calculates the kurtosis using on the specified method.

# Methods
- Excess (default)
- Moment
- Cornish-Fisher

# Arguments
- `x`:          Vector of values.
- `method`:     Estimation method: `:excess`, `:moment` or `:cornish_fisher`.
"""
function kurtosis(x; method::Symbol=:excess)
    n = length(x)
    mean_devs = x .- mean(x)

    if method == :excess
        # Excess
        return sum(mean_devs.^4 / mean(mean_devs.^2)^2 ) / n - 3
    elseif method == :moment
        # Moment
        return sum(mean_devs.^4 / mean(mean_devs.^2)^2 ) / n
    elseif method == :cornish_fisher
        # Cornish-Fisher
        return ((n+1)*(n-1)*((sum(x.^4)/n)/(sum(x.^2)/n)^2 -
            (3*(n-1))/(n+1)))/((n-2)*(n-3))
    end

    throw(ArgumentError("Passed method parameter '$(method)' is invalid, must be one of :excess, :moment, :cornish_fisher."))
end



"""
    volatility(returns; multiplier=1.0)

Calculates the volatility based on the standard deviation of the returns.

# Formula

    Vol = std(returns) * multiplier

# Arguments
- `returns`:    Vector of asset returns (usually log-returns).
- `multiplier`: Optional scalar multiplier, i.e. use `√12` to annualize monthly returns, and use `√252` to annualize daily returns.
"""
function volatility(returns; multiplier=1.0)
    std(returns) * multiplier
end



"""
    tracking_error(asset_returns, benchmark_returns; multiplier=1.0)

Calculates the ex-post Tracking Error based on the standard deviation of the active returns.

# Formula

    TE = std(asset_returns - benchmark_returns) * multiplier

# Arguments
- `asset_returns`:      Vector of asset returns.
- `benchmark_returns`:  Vector of benchmark returns (e.g. market portfolio returns for CAPM beta).
- `multiplier`:         Optional scalar multiplier, i.e. use `√12` to annualize monthly returns, and use `√252` to annualize daily returns.
"""
function tracking_error(asset_returns, benchmark_returns; multiplier=1.0)
    std(asset_returns .- benchmark_returns) * multiplier
end



"""
    capm(asset_returns, benchmark_returns; risk_free=0.0)

Calculates the CAPM alpha and beta coefficients based on sample covariance statistics and a simple linear regression.

# Arguments
- `asset_returns`:      Vector of asset returns.
- `benchmark_returns`:  Vector of benchmark returns (e.g. market portfolio returns for CAPM beta).
- `risk_free`:          Optional vector or scalar value denoting the risk-free return(s). Must have same frequency (e.g. daily) as the provided returns.

# Returns
Tuple containing the alpha and beta coefficients of the CAPM model.
"""
function capm(asset_returns, benchmark_returns; risk_free=0.0)
    asset_returns_ex = asset_returns .- risk_free
    benchmark_returns_ex = benchmark_returns .- risk_free
    μ1 = mean(asset_returns_ex)
    μ2 = mean(benchmark_returns_ex)
    β = sum((asset_returns_ex .- μ1).*(benchmark_returns_ex .- μ2)) / sum((benchmark_returns_ex .- μ2).^2)
    α = μ1 - β*μ2
    (α, β)
end



"""
    sharpe_ratio(returns; multiplier=1.0, risk_free=0.0)

Calculates the Sharpe Ratio (SR) according to the original definition by William F. Sharpe in 1966. For calculating the Sharpe Ratio according to Sharpe's revision in 1994, please see function `information_ratio` (IR).

# Formula

    SR = E[returns - risk_free] / std(returns) * multiplier

    IR = E[asset_returns - benchmark_returns] / std(asset_returns - benchmark_returns) * multiplier

# Arguments
- `returns`:    Vector of asset returns.
- `multiplier`: Optional scalar multiplier, i.e. use `√12` to annualize monthly returns, and use `√252` to annualize daily returns.
- `risk_free`:  Optional vector or scalar value denoting the risk-free return(s). Must have same frequency (e.g. daily) as the provided returns.

# Source
- Sharpe, W. F. (1966). "Mutual Fund Performance". Journal of Business.
- Sharpe, William F. (1994). "The Sharpe Ratio". The Journal of Portfolio Management.
"""
function sharpe_ratio(returns; multiplier=1.0, risk_free=0.0)
    mean(returns .- risk_free) / std(returns) * multiplier
end



"""
    sharpe_ratio_adjusted(returns; multiplier=1.0, risk_free=0.0)

Calculates the adjusted Sharpe Ratio introduced by Pezier and White (2006) by penalizing negative skewness and excess kurtosis.

# Formula

    ASR = SR*[1 + (S/6)SR - (K-3)/24*SR^2] * multiplier

# Arguments
- `returns`:    Vector of asset returns.
- `multiplier`: Optional scalar multiplier, i.e. use `√12` to annualize monthly returns, and use `√252` to annualize daily returns.
- `risk_free`:  Optional vector or scalar value denoting the risk-free return(s). Must have same frequency (e.g. daily) as the provided returns.

# Source
- Pezier, Jaques and White, Anthony (2006). The Relative Merits of Investable Hedge Fund Indices and of Funds of Hedge Funds in Optimal Passive Portfolios. ICMA Centre Discussion Papers in Finance.
"""
function sharpe_ratio_adjusted(returns; multiplier=1.0, risk_free=0.0)
    excess = returns .- risk_free
    SR = mean(excess) / std(excess)
    S = skewness(excess)
    K = kurtosis(excess; method=:excess)
    SR*(1 + (S/6)SR - K/24*SR^2) * multiplier
end



"""
    treynor_ratio(asset_returns, benchmark_returns; multiplier=1.0, risk_free=0.0)

Calculates the Treynor ratio as the ratio of excess return divided by the CAPM beta. This ratio is similar to the Sharpe Ratio, but instead of dividing by the volatility, we devide by the CAPM beta as risk proxy.

# Formula

    TR = E[asset_returns - risk_free] / beta * multiplier

# Arguments
- `asset_returns`:      Vector of asset returns.
- `benchmark_returns`:  Vector of benchmark returns (e.g. market portfolio returns).
- `multiplier`:         Optional scalar multiplier, i.e. use `12` to annualize monthly returns, and use `252` to annualize daily returns. Note that most other measures scale with √, but this ratio not.
- `risk_free`:          Optional vector or scalar value denoting the risk-free return(s). Must have same frequency (e.g. daily) as the provided returns.
"""
function treynor_ratio(asset_returns, benchmark_returns; multiplier=1.0, risk_free=0.0)
    α, β = capm(asset_returns, benchmark_returns; risk_free=risk_free)
    mean(asset_returns .- risk_free) / β * multiplier
end



"""
    omega_ratio(returns, target_return)

This function calculates the Omega ratio.

# Formula

    E[max(returns - target_return, 0)] / E[max(target_return - returns, 0)]

# Arguments
- `returns`:        Vector of asset returns.
- `target_return`:  Vector or scalar value of benchmark returns having same same frequency (e.g. daily) as the provided returns.
"""
function omega_ratio(returns, target_return)
    excess = returns .- target_return
    sum1 = sum(map(x -> max(0.0, x), excess))
    sum2 = -sum(map(x -> min(0.0, x), excess))
    sum1 / sum2
end



"""
    sortino_ratio(returns; multiplier=1.0, risk_free=0.0)

Calculates the Sortino Ratio, a downside risk-adjusted performance measure. Contrary to the Sharpe Ratio, only deviations below the minimum acceptable returns are included in the calculation of the risk (downside deviation instead of standard deviation).

# Arguments
- `returns`:    Vector of asset returns.
- `multiplier`: Optional scalar multiplier, i.e. use `√12` to annualize monthly returns, and use `√252` to annualize daily returns.
- `MAR`:        Optional vector or scalar value denoting the minimum acceptable return(s). Must have same frequency (e.g. daily) as the provided returns.

# Source
- Sortino, F. and Price, L. (1996). Performance Measurement in a Downside Risk Framework. Journal of Investing.
"""
function sortino_ratio(returns; multiplier=1.0, MAR=0.0)
    mean(returns .- MAR) / downside_deviation(returns, MAR; method=:full) * multiplier
end



"""
    information_ratio(asset_returns, benchmark_returns; multiplier=1.0)

This function calculates the Information Ratio as the active return divided by the tracking error. The calculation equals William F. Sharpe's revision of the original version of the Sharpe Ratio (see function `sharpe_ratio`).

# Formula

    IR = E[asset_returns - benchmark_returns] / std(asset_returns - benchmark_returns) * multiplier

# Arguments
- `asset_returns`:      Vector of asset returns.
- `benchmark_returns`:  Vector or scalar value of benchmark returns having same same frequency (e.g. daily) as the provided returns.
- `multiplier`:         Optional scalar multiplier, i.e. use `√12` to annualize monthly returns, and use `√252` to annualize daily returns.

# Source
- Sharpe, William F. (1994). "The Sharpe Ratio". The Journal of Portfolio Management.
"""
function information_ratio(asset_returns, benchmark_returns; multiplier=1.0)
    mean(asset_returns .- benchmark_returns) / std(asset_returns .- benchmark_returns) * multiplier
end



"""
    VaR(returns, confidence, method; multiplier=1.0)

Computes the Value-at-Risk (VaR) for a given significance level `α` based on the chosen estimation method. Please note the capitalization of the function name `VaR`. The VaR value represents the maximum expected loss at a certain significance level `α`. For a more tail-risk focused measure, please see `CVaR`.

# Arguments
- `returns`:     Vector of asset returns.
- `α`:           Significance level, e.g. use `0.05` for 95% confidence, or `0.01` for 99% confidence.
- `method`:      Distribution estimation method: `:historical`, `:gaussian` or `:cornish_fisher`.
- `multiplier`:  Optional scalar multiplier, i.e. use `√12` to annualize monthly returns, and use `√252` to annualize daily returns.

# Methods
- `:historical`:        Historical based on empirical distribution of returns.
- `:gaussian`:          Gaussian distribution based on parametric fit (mean, variance).
- `:cornish_fisher`:    Cornish-Fisher based on Gaussian parametric distribution fit adjusted for third and fourth moments (skewness, kurtosis). Cornish-Fisher expansion aims to approximate the quantile of a true distribution by using higher moments (skewness and kurtosis) of that distribution to adjust for its non-normality. See https://thema.u-cergy.fr/IMG/pdf/2017-21.pdf for details.

# Sources
- Favre, Laurent and Galeano, Jose-Antonio (2002). Mean-Modified Value-at-Risk Optimization with Hedge Funds. Journal of Alternative Investment.
- Amédée-Manesme, Charles-Olivier and Barthélémy, Fabrice and Maillard, Didier (2017). Computation of the Corrected Cornish–Fisher Expansion using the Response Surface Methodology: Application to VaR and CVaR. THEMA Working Paper n°2017-21, Université de Cergy-Pontoise, France.
"""
function VaR(returns, α, method::Symbol; multiplier=1.0)
    if method == :historical
        # empirical quantile for VaR estimation
        return quantile(returns, α) * multiplier
    elseif method == :gaussian
        # parametric Gaussian distribution fit
        μ = mean(returns)
        σ = std(returns; corrected=false)
        return quantile(Normal(μ, σ), α)
    elseif method == :cornish_fisher
        # third/fourth moment adjusted Gaussian distribution fit
        # http://www.diva-portal.org/smash/get/diva2:442078/FULLTEXT01.pdf
        # https://papers.ssrn.com/sol3/papers.cfm?abstract_id=1024151
        q = quantile(Normal(), α)
        S = skewness(returns)
        K = kurtosis(returns; method=:excess)
        z = q + 1/6*(q^2-1)S + 1/24*(q^3-3q)*K - 1/36*(2q^3-5q)*S^2
        μ = mean(returns)
        σ = std(returns; corrected=false)
        return (μ + z*σ) * multiplier
    end

    throw(ArgumentError("Passed method parameter '$(method)' is invalid, must be one of :historical, :gaussian, :cornish_fisher."))
end



"""
    CVaR(returns, confidence, method; multiplier=1.0)

Computes the Conditional Value-at-Risk, also known as Expected Shortfall (ES) or Expected Tail Loss (ETL). Please note the capitalization of the function name `CVaR`. The CVaR is the expected return on the asset in the worst `α%` of cases, therefore quantifies the tail-risk of an asset. It is calculated by averaging all of the returns in the distribution that are worse than the VaR of the portfolio at a given significance level `α`. For instance, for a 5% significance level, the expected shortfall is calculated by taking the average of returns in the worst 5% of cases. 

CVaR is more sensitive to the shape of the tail of the loss distribution.


# Arguments
- `returns`:     Vector of asset returns.
- `α`:           Significance level, e.g. use `0.05` for 95% confidence, or `0.01` for 99% confidence.
- `method`:      Distribution estimation method: `:historical`, `:gaussian` or `:cornish_fisher`.
- `multiplier`:  Optional scalar multiplier, i.e. use `√12` to annualize monthly returns, and use `√252` to annualize daily returns.

# Methods
- `:historical`:        Historical based on empirical distribution of returns.
- `:gaussian`:          Gaussian distribution based on parametric fit (mean, variance).
- `:cornish_fisher`:    Cornish-Fisher based on Gaussian parametric distribution fit adjusted for third and fourth moments (skewness, kurtosis). Cornish-Fisher expansion aims to approximate the quantile of a true distribution by using higher moments (skewness and kurtosis) of that distribution to adjust for its non-normality. See https://thema.u-cergy.fr/IMG/pdf/2017-21.pdf for details.

# Sources
- Amédée-Manesme, Charles-Olivier and Barthélémy, Fabrice and Maillard, Didier (2017). Computation of the Corrected Cornish–Fisher Expansion using the Response Surface Methodology: Application to VaR and CVaR. THEMA Working Paper n°2017-21, Université de Cergy-Pontoise, France.
"""
function CVaR(returns, α, method::Symbol; multiplier=1.0)
    if method == :historical
        # average return below significance level (quantile)
        sorted = sort(returns)
        idx = floor(Int64, length(sorted) * α)
        return mean(sorted[1:idx]) * multiplier
    elseif method == :gaussian
        # derivation: http://blog.smaga.ch/expected-shortfall-closed-form-for-normal-distribution/
        q = quantile(Normal(), α)
        μ = mean(returns)
        σ = std(returns; corrected=false)
        return (μ - σ*pdf(Normal(), q)/α) * multiplier
    elseif method == :cornish_fisher
        # third/fourth moment adjusted Gaussian distribution fit
        # https://papers.ssrn.com/sol3/papers.cfm?abstract_id=1024151
        q = quantile(Normal(), α)
        S = skewness(returns)
        K = kurtosis(returns; method=:excess)
        g = q + 1/6*(q^2-1)S + 1/24*(q^3-3q)*K - 1/36*(2q^3-5q)*S^2
        ϕ = pdf(Normal(), g)
        EG2 = -1/α*ϕ * (1 + 1/6*(g^3)*S + 1/72*(g^6 - 9g^4 + 9g^2 + 3)*S^2 + 1/24*(g^4 - 2g^2 - 1)*K)
        μ = mean(returns)
        σ = std(returns; corrected=false)
        return (μ + σ*EG2) * multiplier
    end

    throw(ArgumentError("Passed method parameter '$(method)' is invalid, must be one of :historical, :gaussian, :cornish_fisher."))
end



"""
    lower_partial_moment(returns, threshold, n, method)

This function calculates the Lower Partial Moment (LPM) for a given threshold.

# Arguments
- `returns`:     Vector of asset returns.
- `threshold`:   Scalar value or vector denoting the threshold returns.
- `n`:           `n`-th moment to calculate.
- `method`:      One of `:full` or `:partial`. Indicates whether to use the number of all returns (`:full`), or only the number of returns below the threshold (`:partial`) in the denominator.
"""
function lower_partial_moment(returns, threshold, n, method::Symbol)
    if method == :full
        denominator = length(returns)
    elseif method == :partial
        denominator = count(returns .< threshold)
    else
        throw(ArgumentError("Passed method parameter '$(method)' is invalid, must be one of :full, :partial."))
    end
    excess = threshold .- returns
    sum(map(x -> max(0.0, x)^n, excess)) / denominator
end



"""
    higher_partial_moment(returns, threshold, n, method)

This function calculates the Higher Partial Moment (HPM) for a given threshold.

# Arguments
- `returns`:     Vector of asset returns.
- `threshold`:   Scalar value or vector denoting the threshold returns.
- `n`:           `n`-th moment to calculate.
- `method`:      One of `:full` or `:partial`. Indicates whether to use the number of all returns (`:full`), or only the number of returns above the threshold (`:partial`) in the denominator.
"""
function higher_partial_moment(returns, threshold, n, method::Symbol)
    if method == :full
        denominator = length(returns)
    elseif method == :partial
        denominator = count(returns .> threshold)
    else
        throw(ArgumentError("Passed method parameter '$(method)' is invalid, must be one of :full, :partial."))
    end
    excess = returns .- threshold
    sum(map(x -> max(0.0, x)^n, excess)) / denominator
end



"""
    downside_deviation(returns, threshold; method=:full)

Calculates the downside deviation / semi-standard deviation which captures the downside risk.

# Arguments
- `returns`:     Vector of asset returns.
- `threshold`:   Scalar value or vector denoting the threshold returns.
- `method`:      One of `:full` (default) or `:partial`. Indicates whether to use the number of all returns (`:full`), or only the number of returns below the threshold (`:partial`) in the denominator.
"""
function downside_deviation(returns, threshold; method::Symbol=:full)
    sqrt(lower_partial_moment(returns, threshold, 2, method))
end



"""
    upside_deviation(returns, threshold; method=:full)

Calculates the upside deviation / semi-standard deviation which captures the upside "risk".

# Arguments
- `returns`:     Vector of asset returns.
- `threshold`:   Scalar value or vector denoting the threshold returns.
- `method`:      One of `:full` (default) or `:partial`. Indicates whether to use the number of all returns (`:full`), or only the number of returns above the threshold (`:partial`) in the denominator.
"""
function upside_deviation(returns, threshold; method::Symbol=:full)
    sqrt(higher_partial_moment(returns, threshold, 2, method))
end



"""
    upside_potential_ratio(returns, threshold; method=:partial)

The Upside Potential Ratio is a risk-adjusted performance measure similarly to the Sharpe Ratio and the Sortino Ratio. This ratio considers only upside returns (above `threshold`) in the numerator, and only downside returns (below `threshold`) in the denominator (see `downside_deviation`).

# Arguments
- `returns`:     Vector of asset returns.
- `threshold`:   Scalar value or vector denoting the threshold returns.
- `method`:      One of `:full` (default) or `:partial`. Indicates whether to use the number of all returns (`:full`), or only the number of returns above the threshold (`:partial`) in the denominator.

# Source
- Plantinga, A., van der Meer, R. and Sortino, F. (2001). The Impact of Downside Risk on Risk-Adjusted Performance of Mutual Funds in the Euronext Markets.
"""
function upside_potential_ratio(returns, threshold; method::Symbol=:partial)
    if method == :full
        n = length(returns)
    elseif method == :partial
        n = count(returns .> threshold)
    else
        throw(ArgumentError("Passed method parameter '$(method)' is invalid, must be one of :full, :partial."))
    end
    dd = downside_deviation(returns, threshold; method=method)
    excess = returns .- threshold
    (sum(map(x -> max(0.0, x), excess)) / n) / dd
end
