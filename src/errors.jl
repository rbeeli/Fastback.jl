struct OrderRejectError <: Exception
    reason::OrderRejectReason.T
end

@inline function Base.showerror(io::IO, err::OrderRejectError)
    print(io, "Order rejected: ", err.reason)
end

"""
Raised when a previous fail-stop mutation poisoned an account.
"""
struct AccountPoisonedError <: Exception end

@inline function Base.showerror(io::IO, ::AccountPoisonedError)
    print(io, "Account is poisoned after a failed mutating operation and cannot advance further.")
end
