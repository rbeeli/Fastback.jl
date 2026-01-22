using Dates
using Printf

mutable struct Instrument{TTime<:Dates.AbstractTime}
    index::UInt                   # unique index for each instrument starting from 1 (used for array indexing and hashing)
    const symbol::Symbol

    const base_symbol::Symbol
    const base_tick::Quantity     # minimum price increment of base asset
    const base_min::Quantity      # minimum quantity of base asset
    const base_max::Quantity      # maximum quantity of base asset
    const base_digits::Int        # number of digits after the decimal point for display

    const quote_symbol::Symbol
    const quote_tick::Price       # minimum price increment of base asset
    const quote_digits::Int       # number of digits after the decimal point for display

    const settlement::SettlementStyle.T
    const margin_mode::MarginMode.T
    const margin_init_long::Price
    const margin_init_short::Price
    const margin_maint_long::Price
    const margin_maint_short::Price
    const contract_kind::ContractKind.T
    const start_time::TTime
    const expiry::TTime
    quote_cash_index::Int

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
        settlement::SettlementStyle.T=SettlementStyle.Cash,
        margin_mode::MarginMode.T=MarginMode.None,
        margin_init_long::Price=0.0,
        margin_init_short::Price=0.0,
        margin_maint_long::Price=0.0,
        margin_maint_short::Price=0.0,
        multiplier::Float64=1.0,
        contract_kind::ContractKind.T=ContractKind.Spot,
        time_type::Type{TTime}=DateTime,
        start_time::TTime=time_type(0),
        expiry::TTime=time_type(0),
    ) where {TTime<:Dates.AbstractTime}
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
            settlement,
            margin_mode,
            margin_init_long,
            margin_init_short,
            margin_maint_long,
            margin_maint_short,
            contract_kind,
            start_time,
            expiry,
            0, # quote_cash_index
            multiplier,
        )
    end
end

@inline Base.hash(inst::Instrument{T}) where {T} = inst.index  # custom hash for better performance

@inline format_base(inst::Instrument, value) = Printf.format(Printf.Format("%.$(inst.base_digits)f"), value)
@inline format_quote(inst::Instrument, value) = Printf.format(Printf.Format("%.$(inst.quote_digits)f"), value)

function Base.show(io::IO, inst::Instrument)
    str = "[Instrument] " *
          "symbol=$(inst.symbol) " *
          "base=$(inst.base_symbol) [$(format_base(inst, inst.base_min)), $(format_base(inst, inst.base_max))]±$(format_base(inst, inst.base_tick)) " *
          "quote=$(inst.quote_symbol)±$(format_quote(inst, inst.quote_tick))"
    print(io, str)
end

@inline has_expiry(inst::Instrument{TTime}) where {TTime<:Dates.AbstractTime} = inst.expiry != TTime(0)
@inline is_expired(inst::Instrument{TTime}, dt::TTime) where {TTime<:Dates.AbstractTime} = has_expiry(inst) && dt >= inst.expiry
@inline is_active(inst::Instrument{TTime}, dt::TTime) where {TTime<:Dates.AbstractTime} = (inst.start_time == TTime(0) || dt >= inst.start_time) && !is_expired(inst, dt)
