mutable struct Cash
    index::Int                # unique index starting from 1 (used for array indexing and hashing)
    const symbol::Symbol
    const digits::Int

    function Cash(
        symbol::Symbol
        ;
        digits=2
    )
        new(
            0, # index
            symbol,
            digits,
        )
    end
end

@inline Base.hash(cash::Cash) = cash.index  # custom hash for better performance

@inline function format_cash(cash::Cash, value)
    Printf.format(Printf.Format("%.$(cash.digits)f"), value)
end

function Base.show(io::IO, cash::Cash)
    print(io, "[Cash] " *
              "index=$(cash.index) " *
              "symbol=$(cash.symbol) " *
              "digits=$(cash.digits)")
end
