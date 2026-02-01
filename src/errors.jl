struct OrderRejectError <: Exception
    reason::OrderRejectReason.T
end

@inline function Base.showerror(io::IO, err::OrderRejectError)
    print(io, "Order rejected: ", err.reason)
end
