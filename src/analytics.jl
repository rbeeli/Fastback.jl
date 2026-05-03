using Dates
import RiskPerf

struct PerformanceSummary
    tot_ret::Float64
    cagr::Float64
    sharpe::Float64
    sortino::Float64
    calmar::Float64
    max_dd::Float64
    avg_dd::Float64
    ulcer::Float64
    vol::Float64
    n_periods::Int
    best_ret::Float64
    worst_ret::Float64
    positive_period_rate::Float64
    expected_shortfall_95::Float64
    skewness::Float64
    kurtosis::Float64
    downside_vol::Float64
    max_dd_duration::Int
    pct_time_in_drawdown::Float64
    omega::Float64
    n_trades::Int
    n_closing_trades::Int
    winners::Union{Missing,Float64}
    losers::Union{Missing,Float64}
end

struct QuoteTradeSummary
    symbol::Symbol
    trade_count::Int
    realized_trade_count::Int
    total_commission::Price
    gross_realized_pnl_quote::Price
    net_realized_pnl_quote::Price
    realized_notional_quote::Price
    gross_realized_return::Float64
    net_realized_return::Float64
    hit_rate::Float64
    average_win_quote::Float64
    average_loss_quote::Float64
    payoff_asymmetry::Float64
end

struct SettlementTradeSummary
    symbol::Symbol
    trade_count::Int
    realized_trade_count::Int
    total_commission::Price
    gross_realized_pnl::Price
end

struct TradeSummary{TPeriod<:Dates.Period}
    trade_count::Int
    realized_trade_count::Int
    finite_realized_count::Int
    hit_rate::Float64
    quote_summaries::Vector{QuoteTradeSummary}
    settlement_summaries::Vector{SettlementTradeSummary}
    average_holding_period::Union{Missing,TPeriod}
    median_holding_period::Union{Missing,TPeriod}
end

struct RealizedHoldingPeriod{TTime<:Dates.AbstractTime,TPeriod<:Dates.Period}
    symbol::Symbol
    entry_date::TTime
    exit_date::TTime
    quantity::Quantity
    holding_period::TPeriod
end

struct HoldingPeriodSummary{TPeriod<:Dates.Period}
    realized_lot_count::Int
    realized_quantity::Quantity
    average_holding_period::Union{Missing,TPeriod}
    median_holding_period::Union{Missing,TPeriod}
end

const PnlConcentrationBucket = Union{Int,Symbol,Dates.Date}

struct PnlConcentrationTable
    bucket::Vector{PnlConcentrationBucket}
    quote_symbol::Vector{Symbol}
    realized_trade_count::Vector{Int}
    gross_realized_pnl_quote::Vector{Price}
    net_realized_pnl_quote::Vector{Price}
    share_of_abs_pnl::Vector{Float64}
    share_of_net_pnl::Vector{Float64}
end

struct PerformanceSummaryTable
    summary::PerformanceSummary
end

function Base.show(io::IO, summary::PerformanceSummary)
    print(io,
        "PerformanceSummary(\n" *
        "    tot_ret=$(summary.tot_ret),\n" *
        "    cagr=$(summary.cagr),\n" *
        "    sharpe=$(summary.sharpe),\n" *
        "    sortino=$(summary.sortino),\n" *
        "    calmar=$(summary.calmar),\n" *
        "    max_dd=$(summary.max_dd),\n" *
        "    avg_dd=$(summary.avg_dd),\n" *
        "    ulcer=$(summary.ulcer),\n" *
        "    vol=$(summary.vol),\n" *
        "    n_periods=$(summary.n_periods),\n" *
        "    best_ret=$(summary.best_ret),\n" *
        "    worst_ret=$(summary.worst_ret),\n" *
        "    positive_period_rate=$(summary.positive_period_rate),\n" *
        "    expected_shortfall_95=$(summary.expected_shortfall_95),\n" *
        "    skewness=$(summary.skewness),\n" *
        "    kurtosis=$(summary.kurtosis),\n" *
        "    downside_vol=$(summary.downside_vol),\n" *
        "    max_dd_duration=$(summary.max_dd_duration),\n" *
        "    pct_time_in_drawdown=$(summary.pct_time_in_drawdown),\n" *
        "    omega=$(summary.omega),\n" *
        "    n_trades=$(summary.n_trades),\n" *
        "    n_closing_trades=$(summary.n_closing_trades),\n" *
        "    winners=$(summary.winners),\n" *
        "    losers=$(summary.losers)\n" *
        ")"
    )
end

function Base.show(io::IO, summary::TradeSummary)
    print(io,
        "TradeSummary(\n" *
        "    trades=$(summary.trade_count),\n" *
        "    realized=$(summary.realized_trade_count),\n" *
        "    hit_rate=$(summary.hit_rate),\n" *
        "    quote_summaries=$(summary.quote_summaries),\n" *
        "    settlement_summaries=$(summary.settlement_summaries),\n" *
        "    avg_holding=$(summary.average_holding_period)\n" *
        ")"
    )
end

function Base.show(io::IO, summary::QuoteTradeSummary)
    print(io,
        "QuoteTradeSummary(\n" *
        "    symbol=$(summary.symbol),\n" *
        "    trades=$(summary.trade_count),\n" *
        "    realized=$(summary.realized_trade_count),\n" *
        "    commission=$(summary.total_commission),\n" *
        "    gross_pnl=$(summary.gross_realized_pnl_quote),\n" *
        "    net_pnl=$(summary.net_realized_pnl_quote),\n" *
        "    realized_notional=$(summary.realized_notional_quote),\n" *
        "    gross_return=$(summary.gross_realized_return),\n" *
        "    net_return=$(summary.net_realized_return),\n" *
        "    hit_rate=$(summary.hit_rate),\n" *
        "    avg_win=$(summary.average_win_quote),\n" *
        "    avg_loss=$(summary.average_loss_quote),\n" *
        "    payoff_asymmetry=$(summary.payoff_asymmetry)\n" *
        ")"
    )
end

function Base.show(io::IO, summary::SettlementTradeSummary)
    print(io,
        "SettlementTradeSummary(\n" *
        "    symbol=$(summary.symbol),\n" *
        "    trades=$(summary.trade_count),\n" *
        "    realized=$(summary.realized_trade_count),\n" *
        "    commission=$(summary.total_commission),\n" *
        "    gross_pnl=$(summary.gross_realized_pnl)\n" *
        ")"
    )
end

function Base.show(io::IO, hp::RealizedHoldingPeriod)
    print(io,
        "RealizedHoldingPeriod(\n" *
        "    symbol=$(hp.symbol),\n" *
        "    entry=$(hp.entry_date),\n" *
        "    exit=$(hp.exit_date),\n" *
        "    quantity=$(hp.quantity),\n" *
        "    period=$(hp.holding_period)\n" *
        ")"
    )
end

function Base.show(io::IO, summary::HoldingPeriodSummary)
    print(io,
        "HoldingPeriodSummary(\n" *
        "    lots=$(summary.realized_lot_count),\n" *
        "    quantity=$(summary.realized_quantity),\n" *
        "    avg=$(summary.average_holding_period),\n" *
        "    median=$(summary.median_holding_period)\n" *
        ")"
    )
end

@inline function _clean_returns(returns)
    out = Float64[]
    sizehint!(out, length(returns))
    @inbounds for r in returns
        (r === nothing || ismissing(r)) && continue
        v = Float64(r)
        isfinite(v) || continue
        push!(out, v)
    end
    out
end

function _return_path_stats(returns::Vector{Float64})
    best_ret = -Inf
    worst_ret = Inf
    n_positive = 0
    @inbounds @simd for r in returns
        best_ret = max(best_ret, r)
        worst_ret = min(worst_ret, r)
        n_positive += r > 0.0
    end
    return (
        best_ret=best_ret,
        worst_ret=worst_ret,
        positive_period_rate=n_positive / length(returns),
    )
end

function _drawdown_duration_stats(returns::Vector{Float64}, compound::Bool)
    n = length(returns)
    n == 0 && return (max_dd_duration=0, pct_time_in_drawdown=NaN)

    wealth = 1.0
    peak = 1.0
    current_duration = 0
    max_duration = 0
    drawdown_periods = 0

    if compound
        @inbounds for r in returns
            wealth *= 1.0 + r
            if wealth >= peak
                peak = wealth
                current_duration = 0
            else
                current_duration += 1
                max_duration = max(max_duration, current_duration)
                drawdown_periods += 1
            end
        end
    else
        @inbounds for r in returns
            wealth += r
            if wealth >= peak
                peak = wealth
                current_duration = 0
            else
                current_duration += 1
                max_duration = max(max_duration, current_duration)
                drawdown_periods += 1
            end
        end
    end

    return (
        max_dd_duration=max_duration,
        pct_time_in_drawdown=drawdown_periods / n,
    )
end

"""
    gross_realized_pnl_quote(t::Trade)

Return gross realized P&L for the closed portion of `t` in quote currency.

This is computed from `realized_return_gross(t)` and `realized_notional_quote(t)`.
It returns `NaN` for non-realizing trades or undefined return bases. This helper
is quote-currency diagnostics only and is not a replacement for
`t.fill_pnl_settle` in cross-currency settlement cases.
"""
@inline gross_realized_pnl_quote(t::Trade) = realized_return_gross(t) * realized_notional_quote(t)

"""
    net_realized_pnl_quote(t::Trade)

Return net realized P&L for the closed portion of `t` in quote currency.

This follows `realized_return_net(t)`, including allocated entry commission and
exit-side commission. It returns `NaN` for non-realizing trades or undefined
return bases. This helper is quote-currency diagnostics only and is not a
replacement for `t.fill_pnl_settle` in cross-currency settlement cases.
"""
@inline net_realized_pnl_quote(t::Trade) = realized_return_net(t) * realized_notional_quote(t)

"""
    trade_summary(acc::Account)
    trade_summary(trades)

Return a compact `TradeSummary` of recorded trades.

Quote-currency return diagnostics are grouped by quote currency. Settlement
cash diagnostics are grouped by settlement currency. No FX conversion is applied
and no raw currency totals are silently summed across currency symbols.
"""
@inline trade_summary(acc::Account) = trade_summary(acc.trades)

function trade_summary(trades::AbstractVector{Trade{TTime}})::TradeSummary where {TTime<:Dates.AbstractTime}
    trade_count = 0
    realized_trade_count = 0
    finite_realized_count = 0
    win_count = 0
    quote_accs = Dict{Symbol,_QuoteTradeAccumulator}()
    settlement_accs = Dict{Symbol,_SettlementTradeAccumulator}()

    @inbounds for t in trades
        trade_count += 1
        inst = t.order.inst
        quote_symbol = inst.spec.quote_symbol
        settle_symbol = inst.spec.settle_symbol

        quote_acc = get!(quote_accs, quote_symbol) do
            _QuoteTradeAccumulator()
        end
        quote_acc.trade_count += 1
        quote_acc.total_commission += t.commission_quote

        settlement_acc = get!(settlement_accs, settle_symbol) do
            _SettlementTradeAccumulator()
        end
        settlement_acc.trade_count += 1
        settlement_acc.total_commission += t.commission_settle

        is_realizing(t) || continue
        realized_trade_count += 1
        settlement_acc.realized_trade_count += 1
        settlement_acc.gross_realized_pnl += t.fill_pnl_settle
        quote_acc.realized_trade_count += 1

        gross_pnl_quote = gross_realized_pnl_quote(t)
        net_pnl_quote = net_realized_pnl_quote(t)
        notional_quote = realized_notional_quote(t)
        if isfinite(gross_pnl_quote) && isfinite(net_pnl_quote) && isfinite(notional_quote) && notional_quote > 0.0
            finite_realized_count += 1
            quote_acc.finite_realized_count += 1
            quote_acc.gross_realized_pnl += gross_pnl_quote
            quote_acc.net_realized_pnl += net_pnl_quote
            quote_acc.realized_notional += notional_quote

            if net_pnl_quote > 0.0
                win_count += 1
                quote_acc.win_count += 1
                quote_acc.win_sum += net_pnl_quote
            elseif net_pnl_quote < 0.0
                quote_acc.loss_count += 1
                quote_acc.loss_sum += net_pnl_quote
            end
        end
    end

    hit_rate = finite_realized_count > 0 ? win_count / finite_realized_count : NaN
    quote_summaries = _quote_trade_summaries(quote_accs)
    settlement_summaries = _settlement_trade_summaries(settlement_accs)
    hp_summary = holding_period_summary(trades)
    TPeriod = _holding_period_summary_type(hp_summary)

    return TradeSummary{TPeriod}(
        trade_count,
        realized_trade_count,
        finite_realized_count,
        hit_rate,
        quote_summaries,
        settlement_summaries,
        hp_summary.average_holding_period,
        hp_summary.median_holding_period,
    )
end

mutable struct _QuoteTradeAccumulator
    trade_count::Int
    realized_trade_count::Int
    finite_realized_count::Int
    total_commission::Price
    gross_realized_pnl::Price
    net_realized_pnl::Price
    realized_notional::Price
    win_count::Int
    win_sum::Price
    loss_count::Int
    loss_sum::Price
end

@inline _QuoteTradeAccumulator() = _QuoteTradeAccumulator(0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0, 0.0, 0, 0.0)

mutable struct _SettlementTradeAccumulator
    trade_count::Int
    realized_trade_count::Int
    total_commission::Price
    gross_realized_pnl::Price
end

@inline _SettlementTradeAccumulator() = _SettlementTradeAccumulator(0, 0, 0.0, 0.0)

function _quote_trade_summaries(accs::Dict{Symbol,_QuoteTradeAccumulator})::Vector{QuoteTradeSummary}
    pairs_sorted = collect(pairs(accs))
    sort!(pairs_sorted; by=p -> p.first)
    summaries = Vector{QuoteTradeSummary}(undef, length(pairs_sorted))
    @inbounds for i in eachindex(pairs_sorted)
        symbol, acc = pairs_sorted[i]
        gross_realized_return = acc.realized_notional > 0.0 ?
            acc.gross_realized_pnl / acc.realized_notional :
            NaN
        net_realized_return = acc.realized_notional > 0.0 ?
            acc.net_realized_pnl / acc.realized_notional :
            NaN
        hit_rate = acc.finite_realized_count > 0 ? acc.win_count / acc.finite_realized_count : NaN
        average_win_quote = acc.win_count > 0 ? acc.win_sum / acc.win_count : NaN
        average_loss_quote = acc.loss_count > 0 ? acc.loss_sum / acc.loss_count : NaN
        payoff_asymmetry = (acc.win_count > 0 && acc.loss_count > 0) ?
            average_win_quote / abs(average_loss_quote) :
            NaN
        summaries[i] = QuoteTradeSummary(
            symbol,
            acc.trade_count,
            acc.realized_trade_count,
            acc.total_commission,
            acc.gross_realized_pnl,
            acc.net_realized_pnl,
            acc.realized_notional,
            gross_realized_return,
            net_realized_return,
            hit_rate,
            average_win_quote,
            average_loss_quote,
            payoff_asymmetry,
        )
    end
    summaries
end

function _settlement_trade_summaries(accs::Dict{Symbol,_SettlementTradeAccumulator})::Vector{SettlementTradeSummary}
    pairs_sorted = collect(pairs(accs))
    sort!(pairs_sorted; by=p -> p.first)
    summaries = Vector{SettlementTradeSummary}(undef, length(pairs_sorted))
    @inbounds for i in eachindex(pairs_sorted)
        symbol, acc = pairs_sorted[i]
        summaries[i] = SettlementTradeSummary(
            symbol,
            acc.trade_count,
            acc.realized_trade_count,
            acc.total_commission,
            acc.gross_realized_pnl,
        )
    end
    summaries
end

@inline _holding_period_summary_type(::HoldingPeriodSummary{TPeriod}) where {TPeriod<:Dates.Period} = TPeriod

"""
    realized_holding_periods(acc::Account)
    realized_holding_periods(trades)

Reconstruct realized holding periods from recorded trades using FIFO lots per
instrument symbol. Returns one `RealizedHoldingPeriod` per consumed lot fragment.

Ordinary open/close and partial exits are exact under the FIFO convention.
Scale-in, reduce, and flip sequences are FIFO approximations because Fastback
stores one netted position per instrument, not full lot identity. If the trade
vector starts after a position is already open, unmatched realized quantity is
skipped because no entry timestamp is available.
"""
@inline realized_holding_periods(acc::Account) = realized_holding_periods(acc.trades)

function realized_holding_periods(trades::AbstractVector{Trade{TTime}}) where {TTime<:Dates.AbstractTime}
    _realized_holding_periods(_holding_period_type(TTime), trades)
end

@inline function _holding_period_type(::Type{TTime}) where {TTime<:Dates.AbstractTime}
    TPeriod = Base.promote_op(-, TTime, TTime)
    (TPeriod === Union{} || !(TPeriod <: Dates.Period) || !isconcretetype(TPeriod)) ? Dates.Period : TPeriod
end

function _realized_holding_periods(
    ::Type{TPeriod},
    trades::AbstractVector{Trade{TTime}},
) where {TTime<:Dates.AbstractTime,TPeriod<:Dates.Period}
    records = RealizedHoldingPeriod{TTime,TPeriod}[]
    lots_by_symbol = Dict{Symbol,Vector{Tuple{TTime,Quantity}}}()

    @inbounds for t in trades
        symbol = t.order.inst.spec.symbol
        lots = get!(lots_by_symbol, symbol) do
            Tuple{TTime,Quantity}[]
        end

        remaining_realized_qty = abs(t.realized_qty)
        if remaining_realized_qty > 0.0
            known_qty = _known_lot_quantity(lots)
            unmatched_qty = max(abs(t.pos_qty) - known_qty, 0.0)
            skipped_qty = min(remaining_realized_qty, unmatched_qty)
            remaining_realized_qty -= skipped_qty

            while remaining_realized_qty > 0.0 && !isempty(lots)
                entry_date, lot_qty = first(lots)
                consumed_qty = min(abs(lot_qty), remaining_realized_qty)
                push!(records, RealizedHoldingPeriod{TTime,TPeriod}(
                    symbol,
                    entry_date,
                    t.date,
                    consumed_qty,
                    t.date - entry_date,
                ))

                remaining_realized_qty -= consumed_qty
                remaining_lot_qty = lot_qty - sign(lot_qty) * consumed_qty
                if remaining_lot_qty == 0.0
                    deleteat!(lots, 1)
                else
                    lots[1] = (entry_date, remaining_lot_qty)
                end
            end
        end

        opened_qty = t.fill_qty + t.realized_qty
        opened_qty != 0.0 && push!(lots, (t.date, opened_qty))
    end

    return records
end

@inline function _known_lot_quantity(lots::Vector{Tuple{TTime,Quantity}}) where {TTime<:Dates.AbstractTime}
    qty = 0.0
    @inbounds for (_, lot_qty) in lots
        qty += abs(lot_qty)
    end
    qty
end

"""
    holding_period_summary(acc::Account)
    holding_period_summary(trades)

Return a compact `HoldingPeriodSummary` of realized FIFO holding periods.

`average_holding_period` and `median_holding_period` are weighted by realized
quantity and use the same period resolution as `t.date - entry_date`. They are
`missing` when no realized exposure can be assigned an entry timestamp.
"""
@inline holding_period_summary(acc::Account) = holding_period_summary(acc.trades)

function holding_period_summary(trades::AbstractVector{Trade{TTime}}) where {TTime<:Dates.AbstractTime}
    _holding_period_summary(realized_holding_periods(trades))
end

function _holding_period_summary(
    periods::AbstractVector{RealizedHoldingPeriod{TTime,TPeriod}},
)::HoldingPeriodSummary{TPeriod} where {TTime<:Dates.AbstractTime,TPeriod<:Dates.Period}
    realized_quantity = 0.0
    weighted_period_value = 0.0

    @inbounds for period in periods
        realized_quantity += period.quantity
        weighted_period_value += Dates.value(period.holding_period) * period.quantity
    end

    if realized_quantity == 0.0
        return HoldingPeriodSummary{TPeriod}(length(periods), realized_quantity, missing, missing)
    end

    period_type = TPeriod === Dates.Period ? typeof(first(periods).holding_period) : TPeriod
    average_holding_period = _period_from_value(period_type, weighted_period_value / realized_quantity)
    median_holding_period = _weighted_median_holding_period(periods, realized_quantity)

    return HoldingPeriodSummary{TPeriod}(
        length(periods),
        realized_quantity,
        average_holding_period,
        median_holding_period,
    )
end

@inline _period_from_value(::Type{TPeriod}, value) where {TPeriod<:Dates.Period} =
    TPeriod(round(Int, value))

function _weighted_median_holding_period(
    periods::AbstractVector{RealizedHoldingPeriod{TTime,TPeriod}},
    total_quantity::Quantity,
) where {TTime<:Dates.AbstractTime,TPeriod<:Dates.Period}
    period_weights = Vector{Tuple{Int64,Quantity}}(undef, length(periods))
    @inbounds for i in eachindex(periods)
        period = periods[i]
        period_weights[i] = (Dates.value(period.holding_period), period.quantity)
    end
    sort!(period_weights; by=first)

    threshold = total_quantity / 2.0
    period_type = TPeriod === Dates.Period ? typeof(first(periods).holding_period) : TPeriod
    cumulative = 0.0
    @inbounds for (period_value, qty) in period_weights
        cumulative += qty
        cumulative >= threshold && return _period_from_value(period_type, period_value)
    end

    return _period_from_value(period_type, last(period_weights)[1])
end

mutable struct _PnlConcentrationBucket
    realized_trade_count::Int
    gross_realized_pnl_quote::Price
    net_realized_pnl_quote::Price
end

@inline _PnlConcentrationBucket() = _PnlConcentrationBucket(0, 0.0, 0.0)

mutable struct _PnlConcentrationTotals
    abs_pnl::Float64
    net_pnl::Float64
end

@inline _PnlConcentrationTotals() = _PnlConcentrationTotals(0.0, 0.0)

"""
    pnl_concentration(acc::Account; by=:instrument, period=:month)
    pnl_concentration(trades; by=:instrument, period=:month)

Return a Tables.jl-compatible view of realized quote-currency P&L concentration.

Supported `by` values are `:instrument`, `:period`, and `:trade`. Period buckets
support `:day`, `:month`, and `:year`. Groups always include quote currency so
different quote currencies are not silently summed together. Period grouping
requires date-bearing timestamps; `Dates.Time`-only trade streams are rejected.
"""
@inline pnl_concentration(acc::Account; by::Symbol=:instrument, period::Symbol=:month) =
    pnl_concentration(acc.trades; by=by, period=period)

function pnl_concentration(
    trades::AbstractVector{Trade{TTime}};
    by::Symbol=:instrument,
    period::Symbol=:month,
) where {TTime<:Dates.AbstractTime}
    by in (:instrument, :period, :trade) ||
        throw(ArgumentError("Unsupported concentration grouping: $(by). Use :instrument, :period, or :trade."))
    if by == :period
        period in (:day, :month, :year) ||
            throw(ArgumentError("Unsupported concentration period: $(period). Use :day, :month, or :year."))
    end

    buckets = Dict{Tuple{PnlConcentrationBucket,Symbol},_PnlConcentrationBucket}()
    @inbounds for t in trades
        is_realizing(t) || continue
        gross_pnl_quote = gross_realized_pnl_quote(t)
        net_pnl_quote = net_realized_pnl_quote(t)
        isfinite(gross_pnl_quote) && isfinite(net_pnl_quote) || continue

        bucket = _pnl_concentration_bucket(t, by, period)
        quote_symbol = t.order.inst.spec.quote_symbol
        agg = get!(buckets, (bucket, quote_symbol)) do
            _PnlConcentrationBucket()
        end
        agg.realized_trade_count += 1
        agg.gross_realized_pnl_quote += gross_pnl_quote
        agg.net_realized_pnl_quote += net_pnl_quote
    end

    sorted_buckets = collect(pairs(buckets))
    sort!(sorted_buckets; by=p -> abs(p.second.net_realized_pnl_quote), rev=true)

    totals_by_quote = Dict{Symbol,_PnlConcentrationTotals}()
    @inbounds for pair in sorted_buckets
        net_pnl_quote = pair.second.net_realized_pnl_quote
        totals = get!(totals_by_quote, pair.first[2]) do
            _PnlConcentrationTotals()
        end
        totals.abs_pnl += abs(net_pnl_quote)
        totals.net_pnl += net_pnl_quote
    end

    n = length(sorted_buckets)
    bucket_col = Vector{PnlConcentrationBucket}(undef, n)
    quote_symbol_col = Vector{Symbol}(undef, n)
    realized_trade_count_col = Vector{Int}(undef, n)
    gross_realized_pnl_quote_col = Vector{Price}(undef, n)
    net_realized_pnl_quote_col = Vector{Price}(undef, n)
    share_of_abs_pnl_col = Vector{Float64}(undef, n)
    share_of_net_pnl_col = Vector{Float64}(undef, n)

    @inbounds for i in 1:n
        key, agg = sorted_buckets[i]
        net_pnl_quote = agg.net_realized_pnl_quote
        bucket_col[i] = key[1]
        quote_symbol_col[i] = key[2]
        realized_trade_count_col[i] = agg.realized_trade_count
        gross_realized_pnl_quote_col[i] = agg.gross_realized_pnl_quote
        net_realized_pnl_quote_col[i] = net_pnl_quote
        totals = totals_by_quote[key[2]]
        share_of_abs_pnl_col[i] = totals.abs_pnl == 0.0 ? NaN : abs(net_pnl_quote) / totals.abs_pnl
        share_of_net_pnl_col[i] = totals.net_pnl == 0.0 ? NaN : net_pnl_quote / totals.net_pnl
    end

    return PnlConcentrationTable(
        bucket_col,
        quote_symbol_col,
        realized_trade_count_col,
        gross_realized_pnl_quote_col,
        net_realized_pnl_quote_col,
        share_of_abs_pnl_col,
        share_of_net_pnl_col,
    )
end

@inline function _pnl_concentration_bucket(t::Trade, by::Symbol, period::Symbol)
    if by == :instrument
        return t.order.inst.spec.symbol
    elseif by == :trade
        return t.tid
    else
        return _calendar_bucket(t.date, period)
    end
end

@inline function _calendar_bucket(dt::Dates.AbstractTime, period::Symbol)
    if period == :day
        return Dates.Date(dt)
    elseif period == :month
        return Dates.Date(Dates.year(dt), Dates.month(dt), 1)
    else
        return Dates.Date(Dates.year(dt), 1, 1)
    end
end

function _calendar_bucket(dt::Dates.Time, period::Symbol)
    throw(ArgumentError(
        "pnl_concentration(...; by=:period) requires date-bearing timestamps; " *
        "Dates.Time has no calendar date. Use by=:instrument or by=:trade, " *
        "or use Date/DateTime-style timestamps."
    ))
end

"""
    performance_summary(returns; periods_per_year=252, risk_free=0.0, mar=0.0, compound=true)
    performance_summary(acc::Account, returns; periods_per_year=252, risk_free=0.0, mar=0.0, compound=true)

Return a `PerformanceSummary` for a periodic return series.

When an account is supplied, trade counts use `acc.trade_count` and win/loss
rates are computed from recorded closing trades when `acc.track_trades == true`.
If trade history is not tracked, win/loss rates are `missing`.
"""
function performance_summary(
    returns;
    periods_per_year::Real=252,
    risk_free=0.0,
    mar=0.0,
    compound::Bool=true
)
    mar isa Real || throw(ArgumentError("mar must be a scalar for summary output."))
    r = _clean_returns(returns)
    _performance_summary(r, periods_per_year, risk_free, mar, compound, 0, 0, missing, missing)
end

function performance_summary(
    acc::Account,
    returns;
    periods_per_year::Real=252,
    risk_free=0.0,
    mar=0.0,
    compound::Bool=true
)
    mar isa Real || throw(ArgumentError("mar must be a scalar for summary output."))
    r = _clean_returns(returns)
    n_trades, n_closing_trades, winners, losers = _trade_win_loss_rates(acc)
    _performance_summary(r, periods_per_year, risk_free, mar, compound, n_trades, n_closing_trades, winners, losers)
end

"""
    performance_summary(pv::PeriodicValues; periods_per_year=252, risk_free=0.0, mar=0.0, compound=true)
    performance_summary(acc::Account, pv::PeriodicValues; periods_per_year=252, risk_free=0.0, mar=0.0, compound=true)

Compute summary metrics from an equity series stored in a `PeriodicValues` collector.
"""
function performance_summary(
    pv::PeriodicValues;
    periods_per_year::Real=252,
    risk_free=0.0,
    mar=0.0,
    compound::Bool=true
)
    eq = values(pv)
    returns = RiskPerf.simple_returns(eq; drop_first=true)
    performance_summary(
        returns;
        periods_per_year=periods_per_year,
        risk_free=risk_free,
        mar=mar,
        compound=compound,
    )
end

function performance_summary(
    acc::Account,
    pv::PeriodicValues;
    periods_per_year::Real=252,
    risk_free=0.0,
    mar=0.0,
    compound::Bool=true
)
    eq = values(pv)
    returns = RiskPerf.simple_returns(eq; drop_first=true)
    performance_summary(
        acc,
        returns;
        periods_per_year=periods_per_year,
        risk_free=risk_free,
        mar=mar,
        compound=compound,
    )
end

function _performance_summary(
    returns::Vector{Float64},
    periods_per_year::Real,
    risk_free,
    mar,
    compound::Bool,
    n_trades::Int,
    n_closing_trades::Int,
    winners::Union{Missing,Float64},
    losers::Union{Missing,Float64},
)::PerformanceSummary
    if isempty(returns)
        return PerformanceSummary(
            NaN,
            NaN,
            NaN,
            NaN,
            NaN,
            NaN,
            NaN,
            NaN,
            NaN,
            0,
            NaN,
            NaN,
            NaN,
            NaN,
            NaN,
            NaN,
            NaN,
            0,
            NaN,
            NaN,
            n_trades,
            n_closing_trades,
            winners,
            losers,
        )
    end

    path_stats = _return_path_stats(returns)
    drawdown_stats = _drawdown_duration_stats(returns, compound)

    PerformanceSummary(
        RiskPerf.total_return(returns),
        RiskPerf.cagr(returns, periods_per_year),
        RiskPerf.sharpe_ratio(returns; multiplier=periods_per_year, risk_free=risk_free),
        RiskPerf.sortino_ratio(returns; multiplier=periods_per_year, MAR=mar),
        RiskPerf.calmar_ratio(returns, periods_per_year; compound=compound),
        RiskPerf.max_drawdown_pct(returns; compound=compound),
        RiskPerf.average_drawdown_pct(returns; compound=compound),
        RiskPerf.ulcer_index(returns; compound=compound),
        RiskPerf.volatility(returns; multiplier=periods_per_year),
        length(returns),
        path_stats.best_ret,
        path_stats.worst_ret,
        path_stats.positive_period_rate,
        RiskPerf.expected_shortfall(returns, 0.05; method=:historical),
        RiskPerf.skewness(returns),
        RiskPerf.kurtosis(returns),
        RiskPerf.downside_deviation(returns, mar; method=:full) * sqrt(Float64(periods_per_year)),
        drawdown_stats.max_dd_duration,
        drawdown_stats.pct_time_in_drawdown,
        RiskPerf.omega_ratio(returns, mar),
        n_trades,
        n_closing_trades,
        winners,
        losers,
    )
end

function _trade_win_loss_rates(acc::Account)
    n_trades = Int(acc.trade_count)
    if !acc.track_trades
        return n_trades, 0, missing, missing
    end

    n_closing_trades = 0
    n_winners = 0
    n_losers = 0
    @inbounds for t in acc.trades
        is_realizing(t) || continue
        n_closing_trades += 1
        ret = realized_return_net(t)
        n_winners += ret > 0.0
        n_losers += ret < 0.0
    end

    if n_closing_trades == 0
        return n_trades, n_closing_trades, missing, missing
    end

    return (
        n_trades,
        n_closing_trades,
        n_winners / n_closing_trades,
        n_losers / n_closing_trades,
    )
end

"""
    performance_summary_table(returns; periods_per_year=252, risk_free=0.0, mar=0.0, compound=true)
    performance_summary_table(pv::PeriodicValues; periods_per_year=252, risk_free=0.0, mar=0.0, compound=true)

Return `performance_summary(args...; kwargs...)` as a one-row Tables.jl source.
The columns mirror the `PerformanceSummary` fields.
"""
function performance_summary_table(
    returns;
    periods_per_year::Real=252,
    risk_free=0.0,
    mar=0.0,
    compound::Bool=true
)
    summary = performance_summary(
        returns;
        periods_per_year=periods_per_year,
        risk_free=risk_free,
        mar=mar,
        compound=compound,
    )
    PerformanceSummaryTable(summary)
end

function performance_summary_table(
    pv::PeriodicValues;
    periods_per_year::Real=252,
    risk_free=0.0,
    mar=0.0,
    compound::Bool=true
)
    summary = performance_summary(
        pv;
        periods_per_year=periods_per_year,
        risk_free=risk_free,
        mar=mar,
        compound=compound,
    )
    PerformanceSummaryTable(summary)
end

function performance_summary_table(
    acc::Account,
    returns;
    periods_per_year::Real=252,
    risk_free=0.0,
    mar=0.0,
    compound::Bool=true
)
    summary = performance_summary(
        acc,
        returns;
        periods_per_year=periods_per_year,
        risk_free=risk_free,
        mar=mar,
        compound=compound,
    )
    PerformanceSummaryTable(summary)
end

function performance_summary_table(
    acc::Account,
    pv::PeriodicValues;
    periods_per_year::Real=252,
    risk_free=0.0,
    mar=0.0,
    compound::Bool=true
)
    summary = performance_summary(
        acc,
        pv;
        periods_per_year=periods_per_year,
        risk_free=risk_free,
        mar=mar,
        compound=compound,
    )
    PerformanceSummaryTable(summary)
end
