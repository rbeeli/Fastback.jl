using Printf

mutable struct Instrument{IData}
    const index::Int                # unique index for each instrument starting from 1 (used for array indexing and hashing)
    const symbol::Symbol
    const price_digits::Int
    const quantity_digits::Int
    data::IData

    function Instrument(
        index::Int,
        symbol::Symbol,
        data::IData=nothing
        ;
        price_digits::Int=2,
        quantity_digits::Int=2
    ) where {IData}
        new{IData}(
            index,
            symbol,
            price_digits,
            quantity_digits,
            data,
        )
    end
end

@inline Base.hash(inst::Instrument) = inst.index  # custom hash for better performance

@inline format_price(inst::Instrument, price) = Printf.format(Printf.Format("%.$(inst.price_digits)f"), price)
@inline format_quantity(inst::Instrument, quantity) = Printf.format(Printf.Format("%.$(inst.quantity_digits)f"), quantity)
