library(PerformanceAnalytics)
library(xts)

# BUFGIX:
#       R = checkData(R, method="matrix") ---> R = checkData(R, method="xts")
DownsideDeviation <- function (R, MAR = 0, method=c("full","subset"), ..., potential=FALSE)
{
    method = method[1] 
    R = checkData(R, method="xts")  # BUG: Removes the time-index which is needed on line 128

    if (ncol(R)==1 || is.vector(R) || is.null(R)) {
        R = na.omit(R)

        r = subset(R, R < MAR)

        if(!is.null(dim(MAR))){
            if(is.timeBased(index(MAR))){
                MAR <-MAR[index(r)] #subset to the same dates as the R data
            } else{
                MAR = mean(checkData(MAR, method = "vector"))
                # we have to assume that Ra and a vector of Rf passed in for MAR both cover the same time period
            }
        }

        switch(method,
            full   = {len = length(R)},
            subset = {len = length(r)} #previously length(R)
        ) # end switch

        if(potential) { # calculates downside potential instead
        	 result = sum((MAR - r)/len)
	}
	else {
	     result = sqrt(sum((MAR - r)^2/len))
	}

        result <- matrix(result, ncol=1)
        return (result)
    }
    else {
        R = checkData(R)
        result = apply(R, MARGIN = 2, DownsideDeviation, MAR = MAR, method = method)
        result<-t(result)
        colnames(result) = colnames(R)
        if(potential)
            rownames(result) = paste("Downside Potential (MAR = ", round(mean(MAR),1),"%)", sep="")
        else
            rownames(result) = paste("Downside Deviation (MAR = ", round(mean(MAR),1),"%)", sep="")
      
        return (result)
    }
}

# BUFGIX: Fix mess with wrong treatment of time-based MAR and non-time based R
#         Also uses index(r) although r hasn't even been declared before.
UpsidePotentialRatio <- function (R, MAR = 0, method=c("subset","full"))
{
    r = subset(R, R > MAR)
    if (!is.null(dim(MAR))) {
        mar <- MAR[index(r)] #subset to the same dates as the R data
    }
    else {
        mar <- MAR
    }
    switch(method,
        full   = {len = length(R)},
        subset = {len = length(r)} #previously length(R)
    ) # end switch
    excess <- r - mar
    (sum(excess)/len)/DownsideDeviation(R, MAR=MAR , method=method)
}


set.seed(5)

# generate random returns
N <- 1000
dts <- seq(as.Date("2010/01/01"), by="day", length.out=N)
asset.rets <- rnorm(N, mean=0.0005, sd=0.001)
market.rets <- rnorm(N, mean=0.0001, sd=0.0005)
rf <- rnorm(N, mean=0.00001, sd=0.0000001)
#rf <- rep(0.000002, N)
# rf <- sample(c(0.0001, 0.001, -0.0001, 0.0, 0.0002), N, replace=T)

# write to CSV
write.csv(asset.rets, 'test/data/recon_asset_rets.csv', row.names=F, quote=F)
write.csv(market.rets, 'test/data/recon_market_rets.csv', row.names=F, quote=F)
write.csv(rf, 'test/data/recon_rf_rets.csv', row.names=F, quote=F)

# read again from CSV to have same precision
asset.rets <- read.csv('test/data/recon_asset_rets.csv')$x
asset.prices <- 1 + cumsum(asset.rets)
market.rets <- read.csv('test/data/recon_market_rets.csv')$x
rf <- read.csv('test/data/recon_rf_rets.csv')$x

asset.prices.ts <- xts(asset.prices, order.by=dts)
asset.rets.ts <- xts(asset.rets, order.by=dts)
market.rets.ts <- xts(market.rets, order.by=dts)
rf.ts <- xts(rf, order.by=dts)

print('-----------------------------------------------------------')
print(paste('var rf', var(rf.ts)))
print(paste('stddev rf', sd(rf.ts)))
print(paste('skewness (default)', skewness(asset.rets.ts)))
print(paste('skewness (moment)', skewness(asset.rets.ts, method='moment')))
print(paste('skewness (fisher)', skewness(asset.rets.ts, method='fisher')))  # bug in R
print(paste('skewness (sample)', skewness(asset.rets.ts, method='sample')))

print(paste('kurtosis (default)', kurtosis(asset.rets.ts)))
print(paste('kurtosis (moment)', kurtosis(asset.rets.ts, method='moment')))
print(paste('kurtosis (excess)', kurtosis(asset.rets.ts, method='excess')))
print(paste('kurtosis (fisher)', kurtosis(asset.rets.ts, method='fisher')))

print(paste('downside_deviation (full)', DownsideDeviation(asset.rets.ts, MAR=0.001, method='full')))
print(paste('downside_deviation (full) rf', DownsideDeviation(asset.rets.ts, MAR=rf.ts, method='full')))
print(paste('downside_deviation (subset)', DownsideDeviation(asset.rets.ts, MAR=0.001, method='subset')))
print(paste('downside_deviation (subset) rf', DownsideDeviation(asset.rets.ts, MAR=rf.ts, method='subset')))

print(paste('lpm (full)', DownsideDeviation(asset.rets.ts, MAR=0.001, method='full')^2))
print(paste('lpm (full) rf', DownsideDeviation(asset.rets.ts, MAR=rf.ts, method='full')^2))
print(paste('lpm (subset)', DownsideDeviation(asset.rets.ts, MAR=0.001, method='subset')^2))
print(paste('lpm (subset) rf', DownsideDeviation(asset.rets.ts, MAR=rf.ts, method='subset')^2))

print(paste('hpm (full)', DownsideDeviation(-asset.rets.ts, MAR=-0.001, method='full')^2))
print(paste('hpm (full) rf', DownsideDeviation(-asset.rets.ts, MAR=-rf.ts, method='full')^2))
print(paste('hpm (subset)', DownsideDeviation(-asset.rets.ts, MAR=-0.001, method='subset')^2))
print(paste('hpm (subset) rf', DownsideDeviation(-asset.rets.ts, MAR=-rf.ts, method='subset')^2))

print(paste('upside_potential_ratio (full)', UpsidePotentialRatio(asset.rets.ts, MAR=0.001, method='full')))
print(paste('upside_potential_ratio (full) rf', UpsidePotentialRatio(asset.rets.ts, MAR=rf.ts, method='full')))
print(paste('upside_potential_ratio (subset)', UpsidePotentialRatio(asset.rets.ts, MAR=0.001, method='subset')))
print(paste('upside_potential_ratio (subset) rf', UpsidePotentialRatio(asset.rets.ts, MAR=rf.ts, method='subset')))

print(paste('volatility', StdDev(asset.rets.ts)))
print(paste('tracking_error', TrackingError(asset.rets.ts, market.rets.ts, scale=1.0)))
# print(paste('information_ratio', InformationRatio(asset.rets.ts, market.rets.ts, scale=1.0))) # don't use - annualizes returns first
print(paste('information_ratio', mean(Return.excess(asset.rets.ts, market.rets.ts)) / TrackingError(asset.rets.ts, market.rets.ts, scale=1.0) ))
print(paste('omega_ratio', Omega(asset.rets.ts, 0.001)))

print(paste('sharpe_ratio', SharpeRatio(asset.rets.ts, Rf=0.0, scale=1)[1]))
print(paste('sharpe_ratio rf', SharpeRatio(asset.rets.ts, Rf=rf.ts, scale=1)[1]))
print(paste('adjusted_sharpe_ratio', AdjustedSharpeRatio(asset.rets.ts, Rf=0.0, scale=1)[1]))

print(paste('sortino_ratio', SortinoRatio(asset.rets.ts, MAR=0.0, scale=1)))
print(paste('sortino_ratio rf', mean(Return.excess(asset.rets.ts, rf.ts)) / DownsideDeviation(asset.rets.ts, rf.ts, method='full')))

print(paste('capm alpha', CAPM.alpha(asset.rets.ts, market.rets.ts, Rf=0.0)))
print(paste('capm beta', CAPM.beta(asset.rets.ts, market.rets.ts, Rf=0.0)))
print(paste('capm alpha rf', CAPM.alpha(asset.rets.ts, market.rets.ts, Rf=rf.ts)))
print(paste('capm beta rf', CAPM.beta(asset.rets.ts, market.rets.ts, Rf=rf.ts)))

print(paste('treynor_ratio', Return.annualized(asset.rets.ts, scale=1.0, geometric=F)/CAPM.beta(asset.rets.ts, market.rets.ts)))
print(paste('treynor_ratio rf', Return.annualized(asset.rets.ts - rf.ts, scale=1.0, geometric=F)/CAPM.beta(asset.rets.ts - rf.ts, market.rets.ts - rf.ts)))

print(paste('VaR (historical)', VaR(asset.rets.ts, p=0.95, method='historical')))
print(paste('VaR (gaussian)', VaR(asset.rets.ts, p=0.95, method='gaussian')))
print(paste('VaR (modified)', VaR(asset.rets.ts, p=0.95, method='modified')))

print(paste('CVaR (historical)', ES(asset.rets.ts, p=0.95, method='historical')))
print(paste('CVaR (gaussian)', ES(asset.rets.ts, p=0.95, method='gaussian')))
print(paste('CVaR (modified)', ES(asset.rets.ts, p=0.95, method='modified')))

print(paste('Return.calculate simple length', length(Return.calculate(asset.prices.ts, method='simple'))))
print(paste('Return.calculate simple mean', mean(Return.calculate(asset.prices.ts, method='simple'), na.rm=T)))
print(paste('Return.calculate simple sd', sd(Return.calculate(asset.prices.ts, method='simple'), na.rm=T)))

print(paste('Return.calculate log length', length(Return.calculate(asset.prices.ts, method='log'))))
print(paste('Return.calculate log mean', mean(Return.calculate(asset.prices.ts, method='log'), na.rm=T)))
print(paste('Return.calculate log sd', sd(Return.calculate(asset.prices.ts, method='log'), na.rm=T)))

print(paste('Return.calculate diff length', length(Return.calculate(asset.prices.ts, method='diff'))))
print(paste('Return.calculate diff mean', mean(Return.calculate(asset.prices.ts, method='diff'), na.rm=T)))
print(paste('Return.calculate diff sd', sd(Return.calculate(asset.prices.ts, method='diff'), na.rm=T)))

dd <- as.vector(Drawdowns(asset.rets.ts))
print(paste('Drawdowns length', length(dd)))
print(paste('Drawdowns mean', mean(dd)))
print(paste('Drawdowns sd', sd(dd)))

dd <- as.vector(Drawdowns(asset.rets.ts, geometric=F))
print(paste('Drawdowns geometric mean', mean(dd)))
print(paste('Drawdowns geometric sd', sd(dd)))

# print(dd[1:10])

#  [1]  0.0 -0.1  0.2 -0.5 -0.1  0.2  0.3 -0.2  0.6  0.8  0.2 -0.8
#  [1]  0.00000000 -0.10000000  0.00000000 -0.45454545 -0.54545455 -0.36363636
#  [7] -0.09090909 -0.27272727  0.00000000  0.00000000  0.00000000 -0.33333333
a <- c(0.0, -0.1, 0.2, -0.5, -0.1, 0.2, 0.3, -0.2, 0.6, 0.8, 0.2, -0.8)
cumrets <- 1+cumsum(a)
print(cumrets)
print(as.vector(cummax(c(1, cumrets))[-1]))

# print(a)
# print(as.vector(Drawdowns(a, geometric=F)))

#     x <- a
#     Return.cumulative = 1+cumsum(x)
#     maxCumulativeReturn = cummax(c(1,Return.cumulative))[-1]
#     column.drawdown = Return.cumulative/maxCumulativeReturn - 1
#     print(Return.cumulative)
#     print(maxCumulativeReturn)
#     print(column.drawdown)

print('-----------------------------------------------------------')
