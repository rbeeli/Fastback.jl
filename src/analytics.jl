using Dates
import RiskPerf

"""
    PerformanceConfig(periods_per_year=252.0; annual_risk_free_rate=0.0,
        annual_minimum_acceptable_return=0.0, expected_shortfall_probability=0.05,
        drawdown_method=:compounded)

Annualization, reference rates, tail probability, and drawdown wealth method of performance
metrics. Annual rates are simple rates converted to per-period rates by dividing by
`periods_per_year`. `expected_shortfall_probability` is the lower-tail probability in `(0, 1]`.
`drawdown_method` is `:compounded` (`wealth *= 1 + r`) or `:additive` (`wealth += r`).
"""
struct PerformanceConfig
    periods_per_year::Float64
    annual_risk_free_rate::Float64
    annual_minimum_acceptable_return::Float64
    expected_shortfall_probability::Float64
    drawdown_method::Symbol

    function PerformanceConfig(
        periods_per_year::Real=252.0;
        annual_risk_free_rate::Real=0.0,
        annual_minimum_acceptable_return::Real=0.0,
        expected_shortfall_probability::Real=0.05,
        drawdown_method::Symbol=:compounded,
    )
        isfinite(periods_per_year) && periods_per_year > 0 ||
            throw(ArgumentError("periods_per_year must be positive and finite, got $(periods_per_year)."))
        isfinite(annual_risk_free_rate) ||
            throw(ArgumentError("annual_risk_free_rate must be finite, got $(annual_risk_free_rate)."))
        isfinite(annual_minimum_acceptable_return) || throw(ArgumentError(
            "annual_minimum_acceptable_return must be finite, got $(annual_minimum_acceptable_return)."))
        isfinite(expected_shortfall_probability) && 0 < expected_shortfall_probability <= 1 || throw(ArgumentError(
            "expected_shortfall_probability must be in (0, 1], got $(expected_shortfall_probability)."))
        drawdown_method in (:compounded, :additive) ||
            throw(ArgumentError("drawdown_method must be :compounded or :additive, got $(repr(drawdown_method))."))
        return new(Float64(periods_per_year), Float64(annual_risk_free_rate),
            Float64(annual_minimum_acceptable_return), Float64(expected_shortfall_probability), drawdown_method)
    end
end

"""
Performance and distribution diagnostics of a periodic return series.

Non-finite observations are ignored and counted in `ignored_observations`. Metrics that cannot be
estimated, such as volatility from one observation or a ratio with a zero denominator, are
`nothing`. Drawdown magnitudes are positive.
"""
struct PerformanceSummary
    observations::Int
    ignored_observations::Int
    total_return::Union{Nothing,Float64}
    annualized_return::Union{Nothing,Float64}
    annualized_volatility::Union{Nothing,Float64}
    sharpe_ratio::Union{Nothing,Float64}
    sortino_ratio::Union{Nothing,Float64}
    maximum_drawdown::Union{Nothing,Float64}
    average_drawdown::Union{Nothing,Float64}
    calmar_ratio::Union{Nothing,Float64}
    ulcer_index::Union{Nothing,Float64}
    omega_ratio::Union{Nothing,Float64}
    expected_shortfall::Union{Nothing,Float64}
    skewness::Union{Nothing,Float64}
    excess_kurtosis::Union{Nothing,Float64}
    annualized_downside_volatility::Union{Nothing,Float64}
    best_return::Union{Nothing,Float64}
    worst_return::Union{Nothing,Float64}
    positive_period_rate::Union{Nothing,Float64}
    maximum_drawdown_duration::Int
    time_in_drawdown_rate::Union{Nothing,Float64}
end

"""
Performance metrics combined with account-level trade diagnostics.

Closing trades, winners, and losers are derived from retained trade history;
`applied_trade_count` remains available when trade retention is disabled.
"""
struct AccountPerformanceSummary
    performance::PerformanceSummary
    applied_trade_count::Int
    closing_trade_count::Int
    winner_rate::Union{Nothing,Float64}
    loser_rate::Union{Nothing,Float64}
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

struct PerformanceSummaryTable{S<:Union{PerformanceSummary,AccountPerformanceSummary}}
    summary::S
end

function _show_fields(io::IO, value)
    print(io, nameof(typeof(value)), "(\n")
    names = fieldnames(typeof(value))
    for (index, name) in enumerate(names)
        print(io, "    ", name, "=", repr(getfield(value, name)), index == length(names) ? "\n" : ",\n")
    end
    print(io, ")")
end

Base.show(io::IO, summary::PerformanceSummary) = _show_fields(io, summary)

function Base.show(io::IO, summary::AccountPerformanceSummary)
    print(io, "AccountPerformanceSummary(\n    performance=")
    show(io, summary.performance)
    print(io,
        ",\n    applied_trade_count=$(summary.applied_trade_count),\n" *
        "    closing_trade_count=$(summary.closing_trade_count),\n" *
        "    winner_rate=$(repr(summary.winner_rate)),\n" *
        "    loser_rate=$(repr(summary.loser_rate))\n)")
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
stores one netted position per instrument, not full lot identity. When the
reconstructed lots disagree with a trade's pre-fill position, for example because
the trade vector starts after the position opened, that exposure has an unknown
entry and its realization records no period. A lot that matches the remaining
realized quantity within rounding noise closes completely.
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
    # A lot without an entry timestamp holds exposure whose opening fill is not in `trades`.
    lots_by_symbol = Dict{Symbol,Vector{Tuple{Union{Nothing,TTime},Quantity}}}()

    @inbounds for t in trades
        symbol = t.order.inst.spec.symbol
        lots = get!(lots_by_symbol, symbol) do
            Tuple{Union{Nothing,TTime},Quantity}[]
        end

        split_factor = t.preceding_split_factor
        isfinite(split_factor) && split_factor > 0.0 ||
            throw(ArgumentError("Trade $(t.tid) has invalid preceding_split_factor $(split_factor)."))
        reconstructed_qty = 0.0
        for i in eachindex(lots)
            entry_date, lot_qty = lots[i]
            if split_factor != 1.0
                lot_qty *= split_factor
                isfinite(lot_qty) || throw(ArgumentError(
                    "Split-adjusted holding quantity is non-finite for $(symbol)."
                ))
                lots[i] = (entry_date, lot_qty)
            end
            reconstructed_qty += lot_qty
        end
        isfinite(reconstructed_qty) ||
            throw(ArgumentError("Reconstructed holding quantity is non-finite for $(symbol)."))
        # Lots that disagree with the recorded pre-fill exposure cannot be attributed; the whole
        # exposure then has an unknown entry.
        if !_quantities_match(reconstructed_qty, t.pos_qty)
            empty!(lots)
            t.pos_qty != 0.0 && push!(lots, (nothing, t.pos_qty))
        end

        remaining_realized_qty = abs(t.realized_qty)
        while remaining_realized_qty > 0.0 && !isempty(lots)
            entry_date, lot_qty = first(lots)
            # A lot that matches the remaining realized quantity within rounding noise closes
            # completely, so subtraction residue never becomes a separate holding period.
            closes_lot = _quantities_match(abs(lot_qty), remaining_realized_qty)
            consumed_qty = closes_lot ? abs(lot_qty) : min(abs(lot_qty), remaining_realized_qty)
            if entry_date !== nothing
                t.date >= entry_date ||
                    throw(ArgumentError("Trade $(t.tid) for $(symbol) exits before its selected entry."))
                push!(records, RealizedHoldingPeriod{TTime,TPeriod}(
                    symbol,
                    entry_date,
                    t.date,
                    consumed_qty,
                    t.date - entry_date,
                ))
            end

            if closes_lot
                remaining_realized_qty = 0.0
                deleteat!(lots, 1)
                continue
            end
            remaining_realized_qty -= consumed_qty
            remaining_lot_qty = lot_qty - sign(lot_qty) * consumed_qty
            if remaining_lot_qty == 0.0
                deleteat!(lots, 1)
            else
                lots[1] = (entry_date, remaining_lot_qty)
            end
        end

        opened_qty = t.fill_qty + t.realized_qty
        opened_qty != 0.0 && push!(lots, (t.date, opened_qty))
    end

    return records
end

@inline function _quantities_match(left::Quantity, right::Quantity)::Bool
    abs(left - right) <= eps(Float64) * 8.0 * max(abs(left), abs(right), 1.0)
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

_finite_option(value) = value isa Real && isfinite(value) ? Float64(value) : nothing

"""
    performance_summary(returns, config=PerformanceConfig()) -> PerformanceSummary

Performance statistics of periodic simple returns. NaN and infinite observations are ignored and
counted.
"""
function performance_summary(returns, config::PerformanceConfig=PerformanceConfig())::PerformanceSummary
    finite = Float64[]
    ignored = 0
    for value in returns
        value isa Real || throw(ArgumentError("Returns must be real numbers, got $(repr(value))."))
        isfinite(value) ? push!(finite, Float64(value)) : (ignored += 1)
    end
    isempty(finite) && return PerformanceSummary(0, ignored, ntuple(_ -> nothing, 17)..., 0, nothing)

    periods = config.periods_per_year
    periodic_risk_free = config.annual_risk_free_rate / periods
    periodic_minimum_return = config.annual_minimum_acceptable_return / periods
    compound = config.drawdown_method == :compounded
    maximum_drawdown = RiskPerf.max_drawdown_pct(finite; compound=compound)
    maximum_drawdown_duration, time_in_drawdown_rate =
        _drawdown_duration_statistics(RiskPerf.drawdowns_pct(finite; compound=compound))
    probability = config.expected_shortfall_probability
    expected_shortfall = probability >= 1.0 ? RiskPerf.mean_excess(finite, 0.0) :
        RiskPerf.expected_shortfall(finite, probability; method=:historical)
    best_return, worst_return = RiskPerf.best_worst_period_return(finite)

    return PerformanceSummary(
        length(finite),
        ignored,
        _finite_option(RiskPerf.total_return(finite)),
        _finite_option(RiskPerf.cagr(finite, periods)),
        _finite_option(RiskPerf.volatility(finite; multiplier=periods)),
        _finite_option(RiskPerf.sharpe_ratio(finite; multiplier=periods, risk_free=periodic_risk_free)),
        _finite_option(RiskPerf.sortino_ratio(finite; multiplier=periods, MAR=periodic_minimum_return)),
        _finite_option(maximum_drawdown),
        _finite_option(RiskPerf.average_drawdown_pct(finite; compound=compound)),
        maximum_drawdown > 0.0 ? _finite_option(RiskPerf.calmar_ratio(finite, periods; compound=compound)) : nothing,
        _finite_option(RiskPerf.ulcer_index(finite; compound=compound)),
        _finite_option(RiskPerf.omega_ratio(finite, periodic_minimum_return)),
        _finite_option(expected_shortfall),
        _finite_option(RiskPerf.skewness(finite)),
        _finite_option(RiskPerf.kurtosis(finite)),
        _finite_option(RiskPerf.downside_deviation(finite, periodic_minimum_return; method=:full) * sqrt(periods)),
        _finite_option(best_return),
        _finite_option(worst_return),
        _finite_option(RiskPerf.hit_rate(finite)),
        maximum_drawdown_duration,
        _finite_option(time_in_drawdown_rate),
    )
end

# Longest run and fraction of observations strictly below the running wealth peak.
function _drawdown_duration_statistics(drawdowns::AbstractVector{Float64})
    current = 0
    maximum_duration = 0
    in_drawdown = 0
    for drawdown in drawdowns
        if drawdown < 0.0
            current += 1
            maximum_duration = max(maximum_duration, current)
            in_drawdown += 1
        else
            current = 0
        end
    end
    return maximum_duration, in_drawdown / length(drawdowns)
end

"""
    performance_summary_from_equity(equity::PeriodicValues, config=PerformanceConfig()) -> PerformanceSummary

Performance statistics of periodically sampled equity. Adjacent observations are converted to
simple returns and the undefined first return is omitted. Deposits, withdrawals, and irregular
sampling are not adjusted.
"""
performance_summary_from_equity(equity::PeriodicValues, config::PerformanceConfig=PerformanceConfig()) =
    performance_summary(RiskPerf.simple_returns(values(equity); drop_first=true), config)

"""
    account_performance_summary(acc::Account, returns, config=PerformanceConfig()) -> AccountPerformanceSummary

Return performance with account trade diagnostics. Winner and loser rates use net realized returns
of retained closing trades; both are `nothing` when trade history is not retained or no closing
trade was retained.
"""
account_performance_summary(acc::Account, returns, config::PerformanceConfig=PerformanceConfig()) =
    _account_performance(acc, performance_summary(returns, config))

"""
    account_performance_summary_from_equity(acc::Account, equity::PeriodicValues, config=PerformanceConfig())

Equity performance with account trade diagnostics; see [`performance_summary_from_equity`](@ref)
and [`account_performance_summary`](@ref).
"""
account_performance_summary_from_equity(acc::Account, equity::PeriodicValues,
    config::PerformanceConfig=PerformanceConfig()) =
    _account_performance(acc, performance_summary_from_equity(equity, config))

function _account_performance(acc::Account, performance::PerformanceSummary)::AccountPerformanceSummary
    applied = Int(acc.trade_count)
    acc.track_trades || return AccountPerformanceSummary(performance, applied, 0, nothing, nothing)
    closing = 0
    winners = 0
    losers = 0
    for trade in acc.trades
        is_realizing(trade) || continue
        closing += 1
        realized = realized_return_net(trade)
        winners += realized > 0.0
        losers += realized < 0.0
    end
    closing == 0 && return AccountPerformanceSummary(performance, applied, 0, nothing, nothing)
    return AccountPerformanceSummary(performance, applied, closing,
        _finite_option(winners / closing), _finite_option(losers / closing))
end

"""
    performance_summary_table(summary::PerformanceSummary)
    performance_summary_table(summary::AccountPerformanceSummary)

One-row Tables.jl source whose columns are the summary's fields; account summaries flatten their
performance fields followed by the trade diagnostics. Undefined metrics are `missing`.
"""
performance_summary_table(summary::Union{PerformanceSummary,AccountPerformanceSummary}) =
    PerformanceSummaryTable(summary)
