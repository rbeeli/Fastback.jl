using Printf

mutable struct Instrument{IData}
    const index::Int              # unique index for each instrument starting from 1 (used for array indexing and hashing)
    const symbol::Symbol

    const base_asset::Symbol
    const base_tick::Quantity     # minimum price increment of base asset
    const base_min::Quantity      # minimum quantity of base asset
    const base_max::Quantity      # maximum quantity of base asset
    const base_digits::Int        # number of digits after the decimal point for display

    const quote_asset::Symbol
    const quote_tick::Price       # minimum price increment of base asset
    const quote_digits::Int       # number of digits after the decimal point for display

    const data::IData

    function Instrument(
        index::Int,
        symbol::Symbol,
        base_asset::Symbol,
        quote_asset::Symbol
        ;
        base_tick::Quantity=0.01,
        base_min::Quantity=-Inf,
        base_max::Quantity=Inf,
        base_digits::Int=2,
        quote_tick::Price=0.01,
        quote_digits::Int=2,
        data::IData=nothing
    ) where {IData}
        new{IData}(
            index,
            symbol,
            base_asset,
            base_tick,
            base_min,
            base_max,
            base_digits,
            quote_asset,
            quote_tick,
            quote_digits,
            data
        )
    end
end

@inline Base.hash(inst::Instrument) = inst.index  # custom hash for better performance

@inline format_base(inst::Instrument, value) = Printf.format(Printf.Format("%.$(inst.base_digits)f"), value)
@inline format_quote(inst::Instrument, value) = Printf.format(Printf.Format("%.$(inst.quote_digits)f"), value)

function Base.show(io::IO, inst::Instrument)
    print(io, "[Instrument] " *
              "index=$(inst.index) " *
              "symbol=$(inst.symbol) " *
              "base=$(inst.base_asset) [$(format_base(inst, inst.base_min)), $(format_base(inst, inst.base_max))] ± $(format_base(inst, inst.base_tick)) " *
              "quote=$(inst.quote_asset) ± $(format_quote(inst, inst.quote_tick)) ")
end
