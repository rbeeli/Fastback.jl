mutable struct Cash
    const index::Int                # unique index starting from 1 (used for array indexing and hashing)
    const symbol::Symbol
    const digits::Int

    function Cash(
        index::Int,
        symbol::Symbol,
        digits::Int,
    )
        index > 0 || throw(ArgumentError("Cash index must be > 0."))
        digits >= 0 || throw(ArgumentError("Cash digits must be >= 0."))
        new(index, symbol, digits)
    end
end

@inline Base.hash(cash::Cash, h::UInt) = hash(cash.index, h)

struct CashSpec
    symbol::Symbol
    digits::Int

    function CashSpec(
        symbol::Symbol;
        digits::Int=2,
    )
        digits >= 0 || throw(ArgumentError("Cash digits must be >= 0."))
        new(symbol, digits)
    end
end

"""
Format a cash value using the cash asset's display precision.
"""
@inline format_cash(cash::Cash, value) = Printf.format(Printf.Format("%.$(cash.digits)f"), value)

function Base.show(io::IO, cash::Cash)
    print(io, "[Cash] " *
              "index=$(cash.index) " *
              "symbol=$(cash.symbol) " *
              "digits=$(cash.digits)")
end

mutable struct CashLedger
    const cash::Vector{Cash}
    const by_symbol::Dict{Symbol,Int}
    const balances::Vector{Price}
    const equities::Vector{Price}
    const interest_borrow_rate::Vector{Price}
    const interest_lend_rate::Vector{Price}
    const init_margin_used::Vector{Price}
    const maint_margin_used::Vector{Price}

    function CashLedger()
        new(
            Vector{Cash}(),
            Dict{Symbol,Int}(),
            Vector{Price}(),
            Vector{Price}(),
            Vector{Price}(),
            Vector{Price}(),
            Vector{Price}(),
            Vector{Price}(),
        )
    end
end

@inline has_cash_asset(ledger::CashLedger, symbol::Symbol)::Bool = haskey(ledger.by_symbol, symbol)

@inline function cash_index(ledger::CashLedger, symbol::Symbol)::Int
    idx = get(ledger.by_symbol, symbol, 0)
    idx > 0 || throw(ArgumentError("Cash with symbol '$(symbol)' not registered."))
    idx
end

@inline function cash_asset(ledger::CashLedger, symbol::Symbol)::Cash
    @inbounds ledger.cash[cash_index(ledger, symbol)]
end

function _register_cash_asset!(
    ledger::CashLedger,
    spec::CashSpec,
)::Cash
    symbol = spec.symbol
    !has_cash_asset(ledger, symbol) || throw(ArgumentError("Cash with symbol '$(symbol)' already registered."))

    idx = length(ledger.cash) + 1
    cash = Cash(idx, symbol, spec.digits)
    push!(ledger.cash, cash)
    ledger.by_symbol[symbol] = idx

    push!(ledger.balances, zero(Price))
    push!(ledger.equities, zero(Price))
    push!(ledger.interest_borrow_rate, zero(Price))
    push!(ledger.interest_lend_rate, zero(Price))
    push!(ledger.init_margin_used, zero(Price))
    push!(ledger.maint_margin_used, zero(Price))

    cash
end

@inline function _adjust_cash_idx!(
    ledger::CashLedger,
    idx::Int,
    amount::Price,
)
    @inbounds begin
        ledger.balances[idx] += amount
        ledger.equities[idx] += amount
    end

    nothing
end
