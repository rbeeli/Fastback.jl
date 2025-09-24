using Dates
using Tables

mutable struct Trade{OData,IData}
    const order::Order{OData,IData}
    const tid::Int
    const date::DateTime
    const fill_price::Price         # price at which the order was filled
    const fill_qty::Quantity        # negative = short selling
    const remaining_qty::Quantity   # remaining (unfilled) quantity after the order was (partially) filled
    const realized_pnl::Price       # realized P&L from exposure reduction (covering) incl. commissions
    const realized_qty::Quantity    # quantity of the existing position that was covered by the order
    const commission::Price         # paid commission in quote currency
    const pos_qty::Quantity         # quantity of the existing position
    const pos_price::Price          # average price of the existing position
end

@inline nominal_value(t::Trade) = t.fill_price * abs(t.fill_qty)
@inline is_realizing(t::Trade) = t.realized_qty != 0

@inline function realized_return(t::Trade; zero_value=0.0)
    return if t.realized_pnl != 0 && t.pos_price != 0
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
              "real_pnl=$(ccy_formatter(t.realized_pnl)) $(inst.quote_symbol) " *
              "real_qty=$(format_base(inst, t.realized_qty)) $(inst.base_symbol) " *
              "commission=$(ccy_formatter(t.commission)) $(inst.quote_symbol) " *
              "pos_px=$(format_quote(inst, t.pos_price)) $(inst.quote_symbol) " *
              "pos_qty=$(format_base(inst, t.pos_qty)) $(inst.base_symbol)")
end

Base.show(obj::Trade) = Base.show(stdout, obj)

# Tables.jl interface for Vector{Trade}
Tables.istable(::Type{<:Vector{<:Trade}}) = true
Tables.rowaccess(::Type{<:Vector{<:Trade}}) = true
Tables.rows(x::Vector{<:Trade}) = x

Tables.schema(x::Vector{<:Trade}) = Tables.Schema((:id, :symbol, :date, :quantity, :filled, :price, :currency, :pnl, :commission, :realized_pnl, :realized_qty, :pos_qty, :pos_price), Tuple{Int, String, DateTime, Float64, Float64, Float64, String, Float64, Float64, Float64, Float64, Float64, Float64})

# Tables.jl interface for individual Trade objects
Tables.getcolumn(t::Trade, nm::Symbol) = Tables.getcolumn(t, Val(nm))
Tables.getcolumn(t::Trade, ::Val{:id}) = t.tid
Tables.getcolumn(t::Trade, ::Val{:symbol}) = string(t.order.inst.symbol)
Tables.getcolumn(t::Trade, ::Val{:date}) = t.date
Tables.getcolumn(t::Trade, ::Val{:quantity}) = Float64(t.order.quantity)
Tables.getcolumn(t::Trade, ::Val{:filled}) = Float64(t.fill_qty)
Tables.getcolumn(t::Trade, ::Val{:price}) = Float64(t.fill_price)
Tables.getcolumn(t::Trade, ::Val{:currency}) = string(t.order.inst.quote_symbol)
Tables.getcolumn(t::Trade, ::Val{:pnl}) = Float64(t.fill_price * t.fill_qty - t.commission)
Tables.getcolumn(t::Trade, ::Val{:commission}) = Float64(t.commission)
Tables.getcolumn(t::Trade, ::Val{:realized_pnl}) = Float64(t.realized_pnl)
Tables.getcolumn(t::Trade, ::Val{:realized_qty}) = Float64(t.realized_qty)
Tables.getcolumn(t::Trade, ::Val{:pos_qty}) = Float64(t.pos_qty)
Tables.getcolumn(t::Trade, ::Val{:pos_price}) = Float64(t.pos_price)

Tables.columnnames(::Trade) = (:id, :symbol, :date, :quantity, :filled, :price, :currency, :pnl, :commission, :realized_pnl, :realized_qty, :pos_qty, :pos_price)
