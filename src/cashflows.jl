using Dates
using EnumX

@enumx CashflowKind::Int8 begin
    BorrowInterest = 1
    LendInterest = 2
    BorrowFee = 3
    Funding = 4
    VariationMargin = 5
    Other = 6
end

struct Cashflow{TTime<:Dates.AbstractTime}
    id::Int                    # sequence id
    dt::TTime                  # event time
    kind::CashflowKind.T       # category
    cash_index::Int            # index into Account.cash arrays
    amount::Price              # movement amount in settlement currency of cash_index
    inst_index::Int            # instrument index, 0 if not tied to an instrument
end
