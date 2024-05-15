using Printf

mutable struct Asset{AData}
    index::UInt              # unique index for each asset starting from 1 (used for array indexing and hashing)
    const symbol::Symbol
    const digits::Int
    const data::AData

    function Asset(
        symbol::Symbol
        ;
        digits=2,
        data::AData=nothing
    ) where {AData}
        new{AData}(
            0, # index
            symbol,
            digits,
            data
        )
    end
end

@inline Base.hash(asset::Asset) = asset.index  # custom hash for better performance

@inline format_value(asset::Asset, value) = Printf.format(Printf.Format("%.$(asset.digits)f"), value)

function Base.show(io::IO, asset::Asset)
    print(io, "[Asset] " *
              "index=$(asset.index) " *
              "symbol=$(asset.symbol) " *
              "digits=$(asset.digits)")
end
