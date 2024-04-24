mutable struct Account{OData,IData}
    const positions::Vector{Position{OData,IData}}
    const executions::Vector{Execution{OData,IData}}
    const initial_balance::Price
    balance::Price
    equity::Price
    order_seq::Int
    execution_seq::Int
    const ccy_digits::Int # number of decimal digits for currency (balance, equity)
    const date_format::String

    function Account{OData}(
        instruments::Vector{Instrument{IData}},
        initial_balance
        ;
        ccy_digits=2,
        date_format="yyyy-mm-dd HH:MM:SS"
    ) where {OData,IData}
        acc = new{OData,IData}(
            Vector{Position{OData,IData}}(),
            Vector{Execution{OData,IData}}(),
            initial_balance,
            initial_balance,
            initial_balance,
            0, # order_seq
            0, # execution_seq
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

@inline format_ccy(acc::Account, x) = Printf.format(Printf.Format("%.$(acc.ccy_digits)f"), x)
@inline format_date(acc::Account, x) = Dates.format(x, acc.date_format)
@inline executions(acc::Account{O,I}) where {O,I} = acc.executions
@inline positions(acc::Account{O,I}) where {O,I} = acc.positions
@inline initial_balance(acc::Account) = acc.initial_balance
@inline balance(acc::Account) = acc.balance
@inline equity(acc::Account) = acc.equity
@inline oid!(acc::Account) = acc.order_seq += 1
@inline eid!(acc::Account) = acc.execution_seq += 1

"""
Calculates the account return as the ratio of the current equity to the initial balance.
"""
@inline function total_return(acc::Account{O,I}) where {O,I}
    acc.equity / acc.initial_balance - one(Price)
end

# TODO: note: slow
@inline function has_positions(acc::Account{O,I}) where {O,I}
    any(map(x -> x.quantity != zero(Quantity), acc.positions))
end

@inline function get_position(acc::Account{O,I}, inst::Instrument{I}) where {O,I}
    @inbounds acc.positions[inst.index]
end

@inline function has_position_with_inst(acc::Account{O,I}, inst::Instrument{I}) where {O,I}
    @inbounds acc.positions[inst.index].quantity != zero(Quantity)
end

@inline function has_position_with_dir(acc::Account{O,I}, inst::Instrument{I}, dir::TradeDir.T) where {O,I}
    sign(@inbounds acc.positions[inst.index].quantity) == sign(dir)
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
