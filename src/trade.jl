using Dates

mutable struct Trade{TTime<:Dates.AbstractTime}
    const order::Order{TTime}
    const tid::Int
    const date::TTime
    const fill_price::Price         # price at which the order was filled
    const fill_qty::Quantity        # negative = short selling
    const remaining_qty::Quantity   # remaining (unfilled) quantity after the order was (partially) filled
    const realized_pnl_entry::Price  # gross realized P&L on entry basis in settlement currency; excludes commissions
    const realized_pnl_settle::Price # gross realized P&L on settlement basis in settlement currency; excludes commissions
    const realized_qty::Quantity    # quantity of the existing position that was covered by the order
    const commission_settle::Price   # paid commission in settlement currency
    const cash_delta_settle::Price   # actual cash movement for this fill in settlement currency
    const pos_qty::Quantity         # quantity of the existing position
    const pos_price::Price          # average entry price of the existing position
    const reason::TradeReason.T
end

@inline nominal_value(t::Trade) = t.fill_price * abs(t.fill_qty) * t.order.inst.multiplier
@inline is_realizing(t::Trade) = t.realized_qty != 0

@inline function realized_return(t::Trade; zero_value=0.0)
    return if t.realized_qty != 0 && t.pos_price != 0
        sign(t.pos_qty) * (t.fill_price / t.pos_price - 1)
    else
        zero_value
    end
end

function Base.show(io::IO, t::Trade)
    date_formatter = x -> Dates.format(x, "yyyy-mm-dd HH:MM:SS")
    ccy_formatter = x -> @sprintf("%.2f", x)
    inst = t.order.inst
    print(io, "[Trade] " *
              "date=$(date_formatter(t.date)) " *
              "fill_px=$(format_quote(inst, t.fill_price)) $(inst.quote_symbol) " *
              "fill_qty=$(format_base(inst, t.fill_qty)) $(inst.base_symbol) " *
              "remain_qty=$(format_base(inst, t.remaining_qty)) $(inst.base_symbol) " *
              "real_pnl_entry=$(ccy_formatter(t.realized_pnl_entry)) $(inst.settle_symbol) " *
              "real_pnl_settle=$(ccy_formatter(t.realized_pnl_settle)) $(inst.settle_symbol) " *
              "real_qty=$(format_base(inst, t.realized_qty)) $(inst.base_symbol) " *
              "commission=$(ccy_formatter(t.commission_settle)) $(inst.settle_symbol) " *
              "cash_delta=$(ccy_formatter(t.cash_delta_settle)) $(inst.settle_symbol) " *
              "pos_px=$(format_quote(inst, t.pos_price)) $(inst.quote_symbol) " *
              "pos_qty=$(format_base(inst, t.pos_qty)) $(inst.base_symbol) " *
              "reason=$(t.reason)")
end

Base.show(obj::Trade) = Base.show(stdout, obj)
