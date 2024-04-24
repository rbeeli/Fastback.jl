using Printf

struct Instrument{IData}
    index::Int64                # unique index for each instrument starting from 1 (used for array indexing and hashing)
    symbol::String
    data::IData
    price_digits::Int
    quantity_digits::Int
    price_formatter::Function
    quantity_formatter::Function

    function Instrument(
        index,
        symbol,
        data::TData=nothing
        ;
        price_digits=2,
        quantity_digits=2
    ) where {TData}
        price_format = Printf.Format("%.$(price_digits)f")
        price_formatter = x -> Printf.format(price_format, x)
        quantity_format = Printf.Format("%.$(quantity_digits)f")
        quantity_formatter = x -> Printf.format(quantity_format, x)
        new{TData}(
            index,
            symbol,
            data,
            price_digits,
            quantity_digits,
            price_formatter,
            quantity_formatter
        )
    end
end

Base.hash(inst::Instrument) = inst.index  # custom hash for better performance
