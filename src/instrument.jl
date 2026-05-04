using Dates
using Printf

struct InstrumentSpec{TTime<:Dates.AbstractTime}
    symbol::Symbol
    base_symbol::Symbol
    base_tick::Quantity     # minimum price increment of base asset
    base_min::Quantity      # minimum quantity of base asset
    base_max::Quantity      # maximum quantity of base asset
    base_digits::Int        # number of digits after the decimal point for display
    quote_symbol::Symbol
    quote_tick::Price       # minimum price increment of quote currency
    quote_digits::Int       # number of digits after the decimal point for display
    settle_symbol::Symbol   # currency used for settlement cashflows
    margin_symbol::Symbol   # currency used for margin requirements
    settlement::SettlementStyle.T
    margin_requirement::MarginRequirement.T
    margin_init_long::Price
    margin_init_short::Price
    margin_maint_long::Price
    margin_maint_short::Price
    short_borrow_rate::Price
    contract_kind::ContractKind.T
    start_time::TTime
    expiry::TTime
    multiplier::Float64
    underlying_symbol::Symbol
    strike::Price
    option_right::OptionRight.T
    exercise_style::OptionExerciseStyle.T
    option_short_margin_rate::Price
    option_short_margin_min_rate::Price

    function InstrumentSpec(
        symbol::Symbol,
        base_symbol::Symbol,
        quote_symbol::Symbol;
        base_tick::Quantity=0.01,
        base_min::Quantity=-Inf,
        base_max::Quantity=Inf,
        base_digits=2,
        quote_tick::Price=0.01,
        quote_digits=2,
        contract_kind::ContractKind.T=ContractKind.Spot,
        settle_symbol::Symbol=quote_symbol,
        margin_symbol::Symbol=settle_symbol,
        settlement::SettlementStyle.T=SettlementStyle.PrincipalExchange,
        margin_requirement::MarginRequirement.T=MarginRequirement.PercentNotional,
        margin_init_long::Price=Price(NaN),
        margin_init_short::Price=Price(NaN),
        margin_maint_long::Price=Price(NaN),
        margin_maint_short::Price=Price(NaN),
        short_borrow_rate::Price=0.0,
        multiplier::Float64=1.0,
        underlying_symbol::Symbol=base_symbol,
        strike::Price=Price(NaN),
        option_right::OptionRight.T=OptionRight.Null,
        exercise_style::OptionExerciseStyle.T=OptionExerciseStyle.Null,
        option_short_margin_rate::Price=0.20,
        option_short_margin_min_rate::Price=0.10,
        time_type::Type{TTime}=DateTime,
        start_time::TTime=time_type(0),
        expiry::TTime=time_type(0),
    ) where {TTime<:Dates.AbstractTime}
        isfinite(multiplier) || throw(ArgumentError("Instrument $(symbol) must set finite multiplier."))
        multiplier > 0.0 || throw(ArgumentError("Instrument $(symbol) must set positive multiplier."))
        if isnan(margin_init_long) != isnan(margin_init_short)
            throw(ArgumentError("Instrument $(symbol) must set both margin_init_long and margin_init_short, or neither."))
        end
        if isnan(margin_maint_long) != isnan(margin_maint_short)
            throw(ArgumentError("Instrument $(symbol) must set both margin_maint_long and margin_maint_short, or neither."))
        end

        new{TTime}(
            symbol,
            base_symbol,
            base_tick,
            base_min,
            base_max,
            base_digits,
            quote_symbol,
            quote_tick,
            quote_digits,
            settle_symbol,
            margin_symbol,
            settlement,
            margin_requirement,
            margin_init_long,
            margin_init_short,
            margin_maint_long,
            margin_maint_short,
            short_borrow_rate,
            contract_kind,
            start_time,
            expiry,
            multiplier,
            underlying_symbol,
            strike,
            option_right,
            exercise_style,
            option_short_margin_rate,
            option_short_margin_min_rate,
        )
    end
end

mutable struct Instrument{TTime<:Dates.AbstractTime}
    index::Int
    quote_cash_index::Int
    settle_cash_index::Int
    margin_cash_index::Int
    const spec::InstrumentSpec{TTime}

    function Instrument(
        index::Int,
        quote_cash_index::Int,
        settle_cash_index::Int,
        margin_cash_index::Int,
        spec::InstrumentSpec{TTime},
    ) where {TTime<:Dates.AbstractTime}
        index > 0 || throw(ArgumentError("Instrument index must be > 0."))
        quote_cash_index > 0 || throw(ArgumentError("Instrument quote_cash_index must be > 0."))
        settle_cash_index > 0 || throw(ArgumentError("Instrument settle_cash_index must be > 0."))
        margin_cash_index > 0 || throw(ArgumentError("Instrument margin_cash_index must be > 0."))
        new{TTime}(index, quote_cash_index, settle_cash_index, margin_cash_index, spec)
    end
end

"""
Return the symbol identifier of the given instrument.
"""
@inline symbol(inst::Instrument) = inst.spec.symbol

"""
Format a base-asset quantity using the instrument's display precision.
"""
@inline format_base(spec::InstrumentSpec, value) = Printf.format(Printf.Format("%.$(spec.base_digits)f"), value)
@inline format_base(inst::Instrument, value) = format_base(inst.spec, value)

"""
Format a quote-currency value using the instrument's display precision.
"""
@inline format_quote(spec::InstrumentSpec, value) = Printf.format(Printf.Format("%.$(spec.quote_digits)f"), value)
@inline format_quote(inst::Instrument, value) = format_quote(inst.spec, value)

"""
    calc_base_qty_for_notional(inst, price, target_notional)

Convert a target quote-currency notional into a base quantity for `inst`.
The returned quantity is rounded down to the instrument's `base_tick` (toward
zero in absolute terms) and clamped to `[base_min, base_max]`.

- `price` is interpreted in quote currency per base unit.
- `target_notional` is interpreted in quote currency and may be signed.
- Uses `abs(price)` so negative-price contracts remain well-defined.
- Assumes valid inputs (finite non-zero `price`, finite `target_notional`,
  and positive `base_tick`).
"""
@inline function calc_base_qty_for_notional(
    inst::Instrument,
    price::Price,
    target_notional::Price,
)::Quantity
    spec = inst.spec
    step = spec.base_tick
    raw_qty = target_notional / (abs(price) * spec.multiplier)
    qty_abs = floor(abs(raw_qty) / step) * step
    qty = copysign(qty_abs, raw_qty)
    Quantity(clamp(qty, spec.base_min, spec.base_max))
end

"""
    spot_instrument(symbol, base_symbol, quote_symbol; kwargs...)

Convenience constructor for principal-exchange spot exposure.
Defaults to percent-notional margin set to 100% (fully funded) and validates
the resulting instrument before returning it.

For `margin_requirement=MarginRequirement.PercentNotional`, margin parameters are
equity fractions of notional (IMR/MMR-style), e.g. `0.10` for 10%.
"""
function spot_instrument(
    symbol::Symbol,
    base_symbol::Symbol,
    quote_symbol::Symbol;
    margin_requirement::MarginRequirement.T=MarginRequirement.PercentNotional,
    margin_init_long::Price=1.0,
    margin_init_short::Price=1.0,
    margin_maint_long::Price=1.0,
    margin_maint_short::Price=1.0,
    base_tick::Quantity=0.01,
    base_min::Quantity=-Inf,
    base_max::Quantity=Inf,
    base_digits::Int=2,
    quote_tick::Price=0.01,
    quote_digits::Int=2,
    settle_symbol::Symbol=quote_symbol,
    margin_symbol::Symbol=settle_symbol,
    short_borrow_rate::Price=0.0,
    multiplier::Float64=1.0,
    time_type::Type{TTime}=DateTime,
    start_time::TTime=time_type(0),
)::InstrumentSpec{TTime} where {TTime<:Dates.AbstractTime}
    spec = InstrumentSpec(
        symbol, base_symbol, quote_symbol;
        base_tick=base_tick,
        base_min=base_min,
        base_max=base_max,
        base_digits=base_digits,
        quote_tick=quote_tick,
        quote_digits=quote_digits,
        contract_kind=ContractKind.Spot,
        settle_symbol=settle_symbol,
        margin_symbol=margin_symbol,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=margin_requirement,
        margin_init_long=margin_init_long,
        margin_init_short=margin_init_short,
        margin_maint_long=margin_maint_long,
        margin_maint_short=margin_maint_short,
        short_borrow_rate=short_borrow_rate,
        multiplier=multiplier,
        time_type=time_type,
        start_time=start_time,
        expiry=time_type(0),
    )
    validate_instrument_spec(spec)
    spec
end

"""
    perpetual_instrument(symbol, base_symbol, quote_symbol; kwargs...)

Perpetual swap constructor. Uses variation margin settlement and requires
explicit margin parameters. `expiry` is fixed to zero by construction.

For `margin_requirement=MarginRequirement.PercentNotional`, margin parameters are
equity fractions of notional (IMR/MMR-style), e.g. `0.10` for 10%.
"""
function perpetual_instrument(
    symbol::Symbol,
    base_symbol::Symbol,
    quote_symbol::Symbol;
    margin_requirement::MarginRequirement.T,
    margin_init_long::Price,
    margin_init_short::Price,
    margin_maint_long::Price,
    margin_maint_short::Price,
    base_tick::Quantity=0.01,
    base_min::Quantity=-Inf,
    base_max::Quantity=Inf,
    base_digits::Int=2,
    quote_tick::Price=0.01,
    quote_digits::Int=2,
    settle_symbol::Symbol=quote_symbol,
    margin_symbol::Symbol=settle_symbol,
    short_borrow_rate::Price=0.0,
    multiplier::Float64=1.0,
    time_type::Type{TTime}=DateTime,
    start_time::TTime=time_type(0),
)::InstrumentSpec{TTime} where {TTime<:Dates.AbstractTime}
    spec = InstrumentSpec(
        symbol, base_symbol, quote_symbol;
        base_tick=base_tick,
        base_min=base_min,
        base_max=base_max,
        base_digits=base_digits,
        quote_tick=quote_tick,
        quote_digits=quote_digits,
        contract_kind=ContractKind.Perpetual,
        settle_symbol=settle_symbol,
        margin_symbol=margin_symbol,
        settlement=SettlementStyle.VariationMargin,
        margin_requirement=margin_requirement,
        margin_init_long=margin_init_long,
        margin_init_short=margin_init_short,
        margin_maint_long=margin_maint_long,
        margin_maint_short=margin_maint_short,
        short_borrow_rate=short_borrow_rate,
        multiplier=multiplier,
        time_type=time_type,
        start_time=start_time,
        expiry=time_type(0),
    )
    validate_instrument_spec(spec)
    spec
end

"""
    future_instrument(symbol, base_symbol, quote_symbol; expiry, kwargs...)

Future constructor using variation margin settlement. Requires a
non-zero `expiry` and explicit margin parameters.

For `margin_requirement=MarginRequirement.PercentNotional`, margin parameters are
equity fractions of notional (IMR/MMR-style), e.g. `0.10` for 10%.
"""
function future_instrument(
    symbol::Symbol,
    base_symbol::Symbol,
    quote_symbol::Symbol;
    expiry::TTime,
    margin_requirement::MarginRequirement.T,
    margin_init_long::Price,
    margin_init_short::Price,
    margin_maint_long::Price,
    margin_maint_short::Price,
    base_tick::Quantity=0.01,
    base_min::Quantity=-Inf,
    base_max::Quantity=Inf,
    base_digits::Int=2,
    quote_tick::Price=0.01,
    quote_digits::Int=2,
    settle_symbol::Symbol=quote_symbol,
    margin_symbol::Symbol=settle_symbol,
    short_borrow_rate::Price=0.0,
    multiplier::Float64=1.0,
    time_type::Type{TTime}=DateTime,
    start_time::TTime=time_type(0),
)::InstrumentSpec{TTime} where {TTime<:Dates.AbstractTime}
    spec = InstrumentSpec(
        symbol, base_symbol, quote_symbol;
        base_tick=base_tick,
        base_min=base_min,
        base_max=base_max,
        base_digits=base_digits,
        quote_tick=quote_tick,
        quote_digits=quote_digits,
        contract_kind=ContractKind.Future,
        settle_symbol=settle_symbol,
        margin_symbol=margin_symbol,
        settlement=SettlementStyle.VariationMargin,
        margin_requirement=margin_requirement,
        margin_init_long=margin_init_long,
        margin_init_short=margin_init_short,
        margin_maint_long=margin_maint_long,
        margin_maint_short=margin_maint_short,
        short_borrow_rate=short_borrow_rate,
        multiplier=multiplier,
        time_type=time_type,
        start_time=start_time,
        expiry=expiry,
    )
    validate_instrument_spec(spec)
    spec
end

"""
    option_instrument(symbol, underlying_symbol, quote_symbol; strike, expiry, right, kwargs...)

Listed option constructor using principal-exchange premium settlement.
Prices are option premium per underlying unit and `multiplier` is the contract
size, usually `100.0` for US equity options. Quantity is measured in contracts.
Long-option margin is the premium paid; short-option margin uses
`option_short_margin_rate` and `option_short_margin_min_rate`.
Generic `margin_requirement` and `margin_init_*`/`margin_maint_*` settings are
not constructor arguments for options.

V1 options are quote-driven and cash-settled at expiry by Fastback; exercise and
assignment into the underlying are intentionally not modeled.
"""
function option_instrument(
    symbol::Symbol,
    underlying_symbol::Symbol,
    quote_symbol::Symbol;
    strike::Price,
    expiry::TTime,
    right::OptionRight.T,
    exercise_style::OptionExerciseStyle.T=OptionExerciseStyle.American,
    base_tick::Quantity=1.0,
    base_min::Quantity=-Inf,
    base_max::Quantity=Inf,
    base_digits::Int=0,
    quote_tick::Price=0.01,
    quote_digits::Int=2,
    settle_symbol::Symbol=quote_symbol,
    margin_symbol::Symbol=settle_symbol,
    multiplier::Float64=100.0,
    option_short_margin_rate::Price=0.20,
    option_short_margin_min_rate::Price=0.10,
    time_type::Type{TTime}=DateTime,
    start_time::TTime=time_type(0),
)::InstrumentSpec{TTime} where {TTime<:Dates.AbstractTime}
    spec = InstrumentSpec(
        symbol, symbol, quote_symbol;
        base_tick=base_tick,
        base_min=base_min,
        base_max=base_max,
        base_digits=base_digits,
        quote_tick=quote_tick,
        quote_digits=quote_digits,
        contract_kind=ContractKind.Option,
        settle_symbol=settle_symbol,
        margin_symbol=margin_symbol,
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.0,
        margin_init_short=0.0,
        margin_maint_long=0.0,
        margin_maint_short=0.0,
        short_borrow_rate=0.0,
        multiplier=multiplier,
        underlying_symbol=underlying_symbol,
        strike=strike,
        option_right=right,
        exercise_style=exercise_style,
        option_short_margin_rate=option_short_margin_rate,
        option_short_margin_min_rate=option_short_margin_min_rate,
        time_type=time_type,
        start_time=start_time,
        expiry=expiry,
    )
    validate_instrument_spec(spec)
    spec
end

function Base.show(io::IO, spec::InstrumentSpec)
    str = "[InstrumentSpec] " *
          "symbol=$(spec.symbol) " *
          "base=$(spec.base_symbol) [$(format_base(spec, spec.base_min)), $(format_base(spec, spec.base_max))]±$(format_base(spec, spec.base_tick)) " *
          "quote=$(spec.quote_symbol)±$(format_quote(spec, spec.quote_tick)) " *
          "settle=$(spec.settle_symbol) " *
          "margin=$(spec.margin_symbol)"
    print(io, str)
end

function Base.show(io::IO, inst::Instrument)
    spec = inst.spec
    str = "[Instrument] " *
          "index=$(inst.index) " *
          "symbol=$(spec.symbol) " *
          "base=$(spec.base_symbol) [$(format_base(inst, spec.base_min)), $(format_base(inst, spec.base_max))]±$(format_base(inst, spec.base_tick)) " *
          "quote=$(spec.quote_symbol)±$(format_quote(inst, spec.quote_tick)) " *
          "settle=$(spec.settle_symbol) " *
          "margin=$(spec.margin_symbol) " *
          "quote_cash_index=$(inst.quote_cash_index) " *
          "settle_cash_index=$(inst.settle_cash_index) " *
          "margin_cash_index=$(inst.margin_cash_index)"
    print(io, str)
end

"""
Return `true` if the instrument defines a non-zero expiry, i.e. the contract expires.
"""
@inline has_expiry(inst::Instrument{TTime}) where {TTime<:Dates.AbstractTime} = inst.spec.expiry != TTime(0)

"""
Return `true` if the instrument is expired at `dt` (inclusive).
"""
@inline is_expired(inst::Instrument{TTime}, dt::TTime) where {TTime<:Dates.AbstractTime} = has_expiry(inst) && dt >= inst.spec.expiry

"""
Return `true` if the instrument is active at `dt` (after start, before expiry).
"""
@inline is_active(inst::Instrument{TTime}, dt::TTime) where {TTime<:Dates.AbstractTime} = begin
    (inst.spec.start_time == TTime(0) || dt >= inst.spec.start_time) && !is_expired(inst, dt)
end

"""
Throw an `ArgumentError` if the instrument is not active at `dt`.
"""
@inline function ensure_active(inst::Instrument{TTime}, dt::TTime) where {TTime<:Dates.AbstractTime}
    if inst.spec.start_time != TTime(0) && dt < inst.spec.start_time
        throw(ArgumentError("Instrument $(inst.spec.symbol) is not active before $(inst.spec.start_time)"))
    elseif is_expired(inst, dt)
        throw(ArgumentError("Instrument $(inst.spec.symbol) expired at $(inst.spec.expiry)"))
    elseif !is_active(inst, dt)
        throw(ArgumentError("Instrument $(inst.spec.symbol) is not active at $dt"))
    end
    inst
end

"""
Validates instrument configuration for common contract kinds.
Throws an `ArgumentError` when mandatory invariants are violated.
"""
function validate_instrument_spec(spec::InstrumentSpec{TTime}) where {TTime<:Dates.AbstractTime}
    kind = spec.contract_kind
    settlement = spec.settlement

    for (name, value) in (
        ("margin_init_long", spec.margin_init_long),
        ("margin_init_short", spec.margin_init_short),
        ("margin_maint_long", spec.margin_maint_long),
        ("margin_maint_short", spec.margin_maint_short),
    )
        isfinite(value) || throw(ArgumentError("Instrument $(spec.symbol) must explicitly set finite $(name)."))
        value >= 0.0 || throw(ArgumentError("Instrument $(spec.symbol) must set non-negative $(name)."))
    end

    spec.margin_maint_long <= spec.margin_init_long ||
        throw(ArgumentError("Instrument $(spec.symbol) must satisfy margin_maint_long <= margin_init_long."))
    spec.margin_maint_short <= spec.margin_init_short ||
        throw(ArgumentError("Instrument $(spec.symbol) must satisfy margin_maint_short <= margin_init_short."))

    if kind != ContractKind.Option && spec.margin_requirement == MarginRequirement.PercentNotional
        if spec.margin_init_long > 1.0 || spec.margin_init_short > 1.0 || spec.margin_maint_long > 1.0 || spec.margin_maint_short > 1.0
            @warn "Instrument $(spec.symbol) uses PercentNotional margin rates above 1.0. Fastback interprets these rates as equity fractions of notional (IMR/MMR-style), not total collateral ratios. Example: broker short requirement 150% collateral (proceeds + 50% equity) should be configured as 0.50, not 1.50."
        end
    end

    if kind == ContractKind.Spot
        settlement == SettlementStyle.PrincipalExchange || throw(ArgumentError("Spot instrument $(spec.symbol) must use Principal-exchange settlement."))
    elseif kind == ContractKind.Perpetual
        settlement == SettlementStyle.VariationMargin || throw(ArgumentError("Perpetual instrument $(spec.symbol) must use VariationMargin settlement."))
        spec.expiry == TTime(0) || throw(ArgumentError("Perpetual instrument $(spec.symbol) must not define an expiry."))
    elseif kind == ContractKind.Future
        settlement == SettlementStyle.VariationMargin || throw(ArgumentError("Future instrument $(spec.symbol) must use VariationMargin settlement."))
        spec.expiry != TTime(0) || throw(ArgumentError("Future instrument $(spec.symbol) must define an expiry."))
    elseif kind == ContractKind.Option
        settlement == SettlementStyle.PrincipalExchange || throw(ArgumentError("Option instrument $(spec.symbol) must use PrincipalExchange settlement."))
        spec.expiry != TTime(0) || throw(ArgumentError("Option instrument $(spec.symbol) must define an expiry."))
        spec.margin_requirement == MarginRequirement.PercentNotional ||
            throw(ArgumentError("Option instrument $(spec.symbol) uses option-specific margin; generic margin_requirement must be PercentNotional."))
        if spec.margin_init_long != 0.0 || spec.margin_init_short != 0.0 || spec.margin_maint_long != 0.0 || spec.margin_maint_short != 0.0
            throw(ArgumentError("Option instrument $(spec.symbol) uses option-specific margin; generic margin_init_* and margin_maint_* fields must be 0.0."))
        end
        spec.option_right in (OptionRight.Call, OptionRight.Put) ||
            throw(ArgumentError("Option instrument $(spec.symbol) must set option_right to Call or Put."))
        spec.exercise_style in (OptionExerciseStyle.American, OptionExerciseStyle.European) ||
            throw(ArgumentError("Option instrument $(spec.symbol) must set exercise_style to American or European."))
        isfinite(spec.strike) || throw(ArgumentError("Option instrument $(spec.symbol) must set finite strike."))
        spec.strike > 0.0 || throw(ArgumentError("Option instrument $(spec.symbol) must set positive strike."))
        isfinite(spec.option_short_margin_rate) || throw(ArgumentError("Option instrument $(spec.symbol) must set finite option_short_margin_rate."))
        spec.option_short_margin_rate >= 0.0 || throw(ArgumentError("Option instrument $(spec.symbol) must set non-negative option_short_margin_rate."))
        isfinite(spec.option_short_margin_min_rate) || throw(ArgumentError("Option instrument $(spec.symbol) must set finite option_short_margin_min_rate."))
        spec.option_short_margin_min_rate >= 0.0 || throw(ArgumentError("Option instrument $(spec.symbol) must set non-negative option_short_margin_min_rate."))
    else
        throw(ArgumentError("Unsupported contract kind $(kind) for instrument $(spec.symbol)."))
    end

    nothing
end
