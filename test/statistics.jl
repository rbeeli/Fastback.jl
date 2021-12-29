using Fastback
using Statistics


@testset "Statistics" begin

    # load test data produced using R PerformanceAnalytics package
    asset_returns = parse.(Float64, readlines("data/recon_asset_rets.csv")[2:end])
    market_returns = parse.(Float64, readlines("data/recon_market_rets.csv")[2:end])
    rf = parse.(Float64, readlines("data/recon_rf_rets.csv")[2:end])

    @test var(rf) ≈ 1.06370309938329e-14
    @test std(rf) ≈ 1.03135983021606e-07

    @test skewness(asset_returns) ≈ -0.0904045109144944
    @test skewness(asset_returns; method=:moment) ≈ -0.0904045109144944
    @test skewness(asset_returns; method=:fisher_pearson) ≈ -0.09054037810903758                # bug in R's PerformanceAnalytics, corrected here
    @test skewness(asset_returns; method=:sample) ≈ -0.0906763586376902

    @test kurtosis(asset_returns) ≈ 0.0619856901585289
    @test kurtosis(asset_returns; method=:excess) ≈ 0.0619856901585289
    @test kurtosis(asset_returns; method=:moment) ≈ 3.06198569015853
    @test kurtosis(asset_returns; method=:cornish_fisher) ≈ -0.158076535757453

    @test downside_deviation(asset_returns, 0.001; method=:full) ≈ 0.00102022195386797
    @test downside_deviation(asset_returns, rf; method=:full) ≈ 0.000474556578712896            # bug in R's PerformanceAnalytics, corrected here
    @test downside_deviation(asset_returns, 0.001; method=:partial) ≈ 0.00123267724486424
    @test downside_deviation(asset_returns, rf; method=:partial) ≈ 0.00085648312494845          # bug in R's PerformanceAnalytics, corrected here

    @test lower_partial_moment(asset_returns, 0.001, 2, :full) ≈ 1.04085283515417e-06
    @test lower_partial_moment(asset_returns, rf, 2, :full) ≈ 2.25203946399689e-07
    @test lower_partial_moment(asset_returns, 0.001, 2, :partial) ≈ 1.51949319000609e-06
    @test lower_partial_moment(asset_returns, rf, 2, :partial) ≈ 7.33563343321463e-07
    
    @test higher_partial_moment(asset_returns, 0.001, 2, :full) ≈ 2.15200955473486e-07
    @test higher_partial_moment(asset_returns, rf, 2, :full) ≈ 1.0554005124107e-06
    @test higher_partial_moment(asset_returns, 0.001, 2, :partial) ≈ 6.83177636423766e-07
    @test higher_partial_moment(asset_returns, rf, 2, :partial) ≈ 1.5229444623531e-06

    @test upside_potential_ratio(asset_returns, 0.001; method=:full) ≈ 0.199853514985918        # bug in R's PerformanceAnalytics, corrected here
    @test upside_potential_ratio(asset_returns, rf; method=:full) ≈ 1.49034594998309            # bug in R's PerformanceAnalytics, corrected here
    @test upside_potential_ratio(asset_returns, 0.001; method=:partial) ≈ 0.525105446510415     # bug in R's PerformanceAnalytics, corrected here
    @test upside_potential_ratio(asset_returns, rf; method=:partial) ≈ 1.19157955999556         # bug in R's PerformanceAnalytics, corrected here

    @test volatility(asset_returns) ≈ 0.0010120151595378
    @test tracking_error(asset_returns, market_returns) ≈ 0.00111905105002574
    @test information_ratio(asset_returns, market_returns) ≈ 0.34034622188359
    @test omega_ratio(asset_returns, 0.001) ≈ 0.297008426326568

    @test sharpe_ratio(asset_returns) ≈ 0.511256629034303
    @test sharpe_ratio(asset_returns; risk_free=rf) ≈ 0.501375462696111
    @test sharpe_ratio_adjusted(asset_returns) ≈ 0.5069731154546914  # slightly different to R's PerformanceAnalytics due to their annualization (0.506476646827294)

    @test sortino_ratio(asset_returns) ≈ 1.10000435875069
    @test sortino_ratio(asset_returns; MAR=rf) ≈ 1.0692077438794

    α1, β1 = capm(asset_returns, market_returns)
    @test α1 ≈ 0.000512345109212185
    @test β1 ≈ 0.0370188032088717

    α2, β2 = capm(asset_returns, market_returns; risk_free=rf)
    @test α2 ≈ 0.000502715256287843
    @test β2 ≈ 0.037019963055605

    @test treynor_ratio(asset_returns, market_returns) ≈ 0.013976666292467
    @test treynor_ratio(asset_returns, market_returns; risk_free=rf) ≈ 0.0137061068404259

    @test VaR(asset_returns, 0.05, :historical) ≈ -0.00115939244815142
    @test VaR(asset_returns, 0.05, :gaussian) ≈ -0.00114638483011466
    @test VaR(asset_returns, 0.05, :cornish_fisher) ≈ -0.00117095813580772

    @test CVaR(asset_returns, 0.05, :historical) ≈ -0.00164648648602694
    @test CVaR(asset_returns, 0.05, :gaussian) ≈ -0.00156905316259027
    @test CVaR(asset_returns, 0.05, :cornish_fisher) ≈ -0.0016287316713825

    @test length(drawdowns(asset_returns)) == 1000
    @test mean(drawdowns(asset_returns)) ≈ -0.000517982256217951
    @test std(drawdowns(asset_returns)) ≈ 0.000916577011725993

    @test mean(drawdowns(asset_returns; geometric=false)) ≈ -0.000418043468523338
    @test std(drawdowns(asset_returns; geometric=false)) ≈ 0.000757130672676854


end
