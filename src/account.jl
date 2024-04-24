mutable struct Account{OData,IData}
    const positions::Vector{Position{OData,IData}}
    const executions::Vector{Execution{OData,IData}}
    const initial_balance::Price
    balance::Price
    equity::Price
    order_seq::Int
    execution_seq::Int
    const ccy_digits::Int # number of decimal digits for currency (balance, equity)
    const ccy_formatter::Function
    const date_formatter::Function

    function Account{OData}(
        instruments::Vector{Instrument{IData}},
        initial_balance
        ;
        ccy_digits=2,
        date_format="yyyy-mm-dd HH:MM:SS"
    ) where {OData,IData}
        ccy_format = Printf.Format("%.$(ccy_digits)f")
        ccy_formatter = x -> Printf.format(ccy_format, x)
        date_formatter = x -> Dates.format(x, date_format)
        acc = new{OData,IData}(
            Vector{Position{OData,IData}}(),
            Vector{Execution{OData,IData}}(),
            initial_balance,
            initial_balance,
            initial_balance,
            1,
            1,
            ccy_digits,
            ccy_formatter,
            date_formatter,
        )
        for i in instruments
            push!(acc.positions, Position{OData,IData}(i.index, acc, i, 0.0, 0.0, 0.0))
        end
        acc
    end
end

"""
Calculates the account return as the ratio of the current equity to the initial balance.
"""
@inline function total_return(acc::Account{O,I}) where {O,I}
    acc.equity / acc.initial_balance - 1.0
end

# TODO: note: slow
@inline function has_positions(acc::Account{O,I}) where {O,I}
    any(map(x -> x.quantity != 0.0, acc.positions))
end

@inline function get_position(acc::Account{O,I}, inst::Instrument{I}) where {O,I}
    @inbounds acc.positions[inst.index]
end

@inline function has_position_with_inst(acc::Account{O,I}, inst::Instrument{I}) where {O,I}
    @inbounds acc.positions[inst.index].quantity != 0.0
end

@inline function has_position_with_dir(acc::Account{O,I}, inst::Instrument{I}, dir::TradeDir.T) where {O,I}
    sign(acc.positions[inst.index].quantity) == sign(dir)
end

# @inline total_pnl_net(acc::Account) = sum(map(pnl_net, acc.closed_positions))
# @inline total_pnl_gross(acc::Account) = sum(map(pnl_gross, acc.closed_positions))

# @inline count_winners_net(acc::Account) = count(map(x -> pnl_net(x) > 0.0, acc.closed_positions))
# @inline count_winners_gross(acc::Account) = count(map(x -> pnl_gross(x) > 0.0, acc.closed_positions))

@inline function update_pnl!(acc::Account{O,I}, pos::Position{O}, close_price::Price) where {O,I}
    # update P&L and account equity using delta of old and new P&L
    new_pnl = calc_pnl(pos, close_price)
    acc.equity += new_pnl - pos.pnl
    pos.pnl = new_pnl
    nothing
end
