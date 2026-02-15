using Dates
using Printf

mutable struct Instrument{TTime<:Dates.AbstractTime}
    index::Int                    # unique index for each instrument starting from 1 (used for array indexing)
    const symbol::Symbol

    const base_symbol::Symbol
    const base_tick::Quantity     # minimum price increment of base asset
    const base_min::Quantity      # minimum quantity of base asset
    const base_max::Quantity      # maximum quantity of base asset
    const base_digits::Int        # number of digits after the decimal point for display

    const quote_symbol::Symbol
    const quote_tick::Price       # minimum price increment of base asset
    const quote_digits::Int       # number of digits after the decimal point for display

    const settle_symbol::Symbol   # currency used for settlement cashflows
    const margin_symbol::Symbol   # currency used for margin requirements

    const settlement::SettlementStyle.T
    const margin_requirement::MarginRequirement.T
    const margin_init_long::Price
    const margin_init_short::Price
    const margin_maint_long::Price
    const margin_maint_short::Price
    const short_borrow_rate::Price
    const contract_kind::ContractKind.T
    const start_time::TTime
    const expiry::TTime
    quote_cash_index::Int
    settle_cash_index::Int
    margin_cash_index::Int

    const multiplier::Float64

    function Instrument(
        symbol::Symbol,
        base_symbol::Symbol,
        quote_symbol::Symbol
        ;
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
            0, # index
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
            0, # quote_cash_index
            0, # settle_cash_index
            0, # margin_cash_index
            multiplier,
        )
    end
end

"""
Return the symbol identifier of the given instrument.
"""
@inline symbol(inst::Instrument) = inst.symbol

"""
Format a base-asset quantity using the instrument's display precision.
"""
@inline format_base(inst::Instrument, value) = Printf.format(Printf.Format("%.$(inst.base_digits)f"), value)

"""
Format a quote-currency value using the instrument's display precision.
"""
@inline format_quote(inst::Instrument, value) = Printf.format(Printf.Format("%.$(inst.quote_digits)f"), value)

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
    step = inst.base_tick
    raw_qty = target_notional / (abs(price) * inst.multiplier)
    qty_abs = floor(abs(raw_qty) / step) * step
    qty = copysign(qty_abs, raw_qty)
    Quantity(clamp(qty, inst.base_min, inst.base_max))
end

"""
    spot_instrument(symbol, base_symbol, quote_symbol; kwargs...)

Convenience constructor for principal-exchange spot exposure.
Defaults to percent-notional margin set to 100% (fully funded) and validates
the resulting instrument before returning it.
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
)::Instrument{TTime} where {TTime<:Dates.AbstractTime}
    inst = Instrument(
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
    validate_instrument(inst)
    inst
end

"""
    perpetual_instrument(symbol, base_symbol, quote_symbol; kwargs...)

Perpetual swap constructor. Uses variation margin settlement and requires
explicit margin parameters. `expiry` is fixed to zero by construction.
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
)::Instrument{TTime} where {TTime<:Dates.AbstractTime}
    inst = Instrument(
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
    validate_instrument(inst)
    inst
end

"""
    future_instrument(symbol, base_symbol, quote_symbol; expiry, kwargs...)

Future constructor using variation margin settlement. Requires a
non-zero `expiry` and explicit margin parameters.
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
)::Instrument{TTime} where {TTime<:Dates.AbstractTime}
    inst = Instrument(
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
    validate_instrument(inst)
    inst
end

function Base.show(io::IO, inst::Instrument)
    str = "[Instrument] " *
          "symbol=$(inst.symbol) " *
          "base=$(inst.base_symbol) [$(format_base(inst, inst.base_min)), $(format_base(inst, inst.base_max))]±$(format_base(inst, inst.base_tick)) " *
          "quote=$(inst.quote_symbol)±$(format_quote(inst, inst.quote_tick)) " *
          "settle=$(inst.settle_symbol) " *
          "margin=$(inst.margin_symbol)"
    print(io, str)
end

"""
Return `true` if the instrument defines a non-zero expiry, i.e. the contract expires.
"""
@inline has_expiry(inst::Instrument{TTime}) where {TTime<:Dates.AbstractTime} = inst.expiry != TTime(0)

"""
Return `true` if the instrument is expired at `dt` (inclusive).
"""
@inline is_expired(inst::Instrument{TTime}, dt::TTime) where {TTime<:Dates.AbstractTime} = has_expiry(inst) && dt >= inst.expiry

"""
Return `true` if the instrument is active at `dt` (after start, before expiry).
"""
@inline is_active(inst::Instrument{TTime}, dt::TTime) where {TTime<:Dates.AbstractTime} = (inst.start_time == TTime(0) || dt >= inst.start_time) && !is_expired(inst, dt)

"""
Throw an `ArgumentError` if the instrument is not active at `dt`.
"""
@inline function ensure_active(inst::Instrument{TTime}, dt::TTime) where {TTime<:Dates.AbstractTime}
    if inst.start_time != TTime(0) && dt < inst.start_time
        throw(ArgumentError("Instrument $(inst.symbol) is not active before $(inst.start_time)"))
    elseif is_expired(inst, dt)
        throw(ArgumentError("Instrument $(inst.symbol) expired at $(inst.expiry)"))
    elseif !is_active(inst, dt)
        throw(ArgumentError("Instrument $(inst.symbol) is not active at $dt"))
    end
    inst
end

"""
Validates instrument configuration for common contract kinds.
Throws an `ArgumentError` when mandatory invariants are violated.
"""
function validate_instrument(inst::Instrument{TTime}) where {TTime<:Dates.AbstractTime}
    kind = inst.contract_kind
    settlement = inst.settlement

    for (name, value) in (
        ("margin_init_long", inst.margin_init_long),
        ("margin_init_short", inst.margin_init_short),
        ("margin_maint_long", inst.margin_maint_long),
        ("margin_maint_short", inst.margin_maint_short),
    )
        isfinite(value) || throw(ArgumentError("Instrument $(inst.symbol) must explicitly set finite $(name)."))
        value >= 0.0 || throw(ArgumentError("Instrument $(inst.symbol) must set non-negative $(name)."))
    end

    inst.margin_maint_long <= inst.margin_init_long ||
        throw(ArgumentError("Instrument $(inst.symbol) must satisfy margin_maint_long <= margin_init_long."))
    inst.margin_maint_short <= inst.margin_init_short ||
        throw(ArgumentError("Instrument $(inst.symbol) must satisfy margin_maint_short <= margin_init_short."))

    if kind == ContractKind.Spot
        settlement == SettlementStyle.PrincipalExchange || throw(ArgumentError("Spot instrument $(inst.symbol) must use Principal-exchange settlement."))
    elseif kind == ContractKind.Perpetual
        settlement == SettlementStyle.VariationMargin || throw(ArgumentError("Perpetual instrument $(inst.symbol) must use VariationMargin settlement."))
        inst.expiry == TTime(0) || throw(ArgumentError("Perpetual instrument $(inst.symbol) must not define an expiry."))
    elseif kind == ContractKind.Future
        settlement == SettlementStyle.VariationMargin || throw(ArgumentError("Future instrument $(inst.symbol) must use VariationMargin settlement."))
        has_expiry(inst) || throw(ArgumentError("Future instrument $(inst.symbol) must define an expiry."))
    end

    nothing
end
