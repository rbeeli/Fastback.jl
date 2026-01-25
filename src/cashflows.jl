using Dates
using EnumX

@enumx CashflowKind::Int8 begin
    Interest = 1
    BorrowFee = 2
    Funding = 3
    VariationMargin = 4
    Other = 5
end

mutable struct Cashflow{TTime<:Dates.AbstractTime}
    const id::Int                    # sequence id
    const dt::TTime                  # event time
    const kind::CashflowKind.T       # category
    const cash_index::Int            # index into Account.cash arrays
    const amount::Price              # movement amount in settlement currency of cash_index
    const inst_index::Int            # instrument index, 0 if not tied to an instrument
end
