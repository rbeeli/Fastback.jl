mutable struct Account{OData,IData}
    const positions::Vector{Position{OData,IData}}
    const trades::Vector{Trade{OData,IData}}
    const initial_balance::Price
    balance::Price
    equity::Price
    order_seq::Int
    trade_seq::Int
    const ccy_digits::Int # number of decimal digits for currency (balance, equity)
    const date_format::Dates.DateFormat

    function Account{OData}(
        instruments::Vector{Instrument{IData}},
        initial_balance
        ;
        ccy_digits=2,
        date_format=dateformat"yyyy-mm-dd HH:MM:SS"
    ) where {OData,IData}
        acc = new{OData,IData}(
            Vector{Position{OData,IData}}(),
            Vector{Trade{OData,IData}}(),
            initial_balance,
            initial_balance,
            initial_balance,
            0, # order_seq
            0, # trade_seq
            ccy_digits,
            date_format,
        )
        resize!(acc.positions, length(instruments))
        for (i, inst) in enumerate(instruments)
            @inbounds acc.positions[i] = Position{OData}(inst.index, inst, 0.0, 0.0, 0.0)
        end
        acc
    end
end

@inline ccy_digits(acc::Account) = acc.ccy_digits
@inline date_format(acc::Account) = acc.date_format
@inline format_ccy(acc::Account, x) = Printf.format(Printf.Format("%.$(ccy_digits(acc))f"), x)
@inline format_date(acc::Account, x) = Dates.format(x, date_format(acc))
@inline trades(acc::Account) = acc.trades
@inline positions(acc::Account) = acc.positions
@inline initial_balance(acc::Account) = acc.initial_balance
@inline balance(acc::Account) = acc.balance
@inline equity(acc::Account) = acc.equity
@inline oid!(acc::Account) = acc.order_seq += 1
@inline tid!(acc::Account) = acc.trade_seq += 1

"""
Calculates the account return as the ratio of the current equity to the initial balance.
"""
@inline function total_return(acc::Account{O,I}) where {O,I}
    acc.equity / acc.initial_balance - one(Price)
end

# # TODO: note: slow
# @inline function has_positions(acc::Account{O,I}) where {O,I}
#     any(map(x -> x.quantity != zero(Quantity), acc.positions))
# end

@inline function get_position(acc::Account{O,I}, inst::Instrument{I}) where {O,I}
    @inbounds acc.positions[inst.index]
end

@inline function is_exposed_to(acc::Account{O,I}, inst::Instrument{I}) where {O,I}
    has_exposure(@inbounds acc.positions[inst.index])
end

@inline function is_exposed_to(acc::Account{O,I}, inst::Instrument{I}, dir::TradeDir.T) where {O,I}
    trade_dir(@inbounds acc.positions[inst.index].quantity) == sign(dir)
end

# @inline total_pnl_net(acc::Account) = sum(map(pnl_net, acc.closed_positions))
# @inline total_pnl_gross(acc::Account) = sum(map(pnl_gross, acc.closed_positions))

# @inline count_winners_net(acc::Account) = count(map(x -> pnl_net(x) > 0.0, acc.closed_positions))
# @inline count_winners_gross(acc::Account) = count(map(x -> pnl_gross(x) > 0.0, acc.closed_positions))

@inline function update_pnl!(acc::Account, pos::Position, close_price)
    # update P&L and account equity using delta of old and new P&L
    new_pnl = calc_pnl(pos, close_price)
    acc.equity += new_pnl - pos.pnl
    pos.pnl = new_pnl
    return
end

@inline function update_pnl!(acc::Account, inst::Instrument, close_price)
    update_pnl!(acc, get_position(acc, inst), close_price)
end
