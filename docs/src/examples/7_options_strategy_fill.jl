# # Atomic option strategy fill example
#
# This example demonstrates `fill_option_strategy!`, which is useful when a
# multi-leg listed-option package has lower final risk than its temporary
# single-leg path.
#
# The concrete case is a 100/105 debit call spread:
#
# - buy 1 C100 at 5.00
# - sell 1 C105 at 2.00
# - net debit = 3.00 x 100 = 300
# - maximum loss = 300
#
# A single-leg fill would need 500 of buying power for the long call before the
# short call exists. `fill_option_strategy!` checks the final package margin
# first, so an account with exactly 300 can enter the complete spread.
#
# !!! warning "Cash-settled proxy"
#     This example uses AAPL-like option symbols, but Fastback treats these
#     options as cash-settled, assignment-free contracts. It does not model
#     OCC/IBKR physical delivery, early exercise, short assignment, or pin risk.
#     See [Options limitations / IBKR mapping](@ref).

using Fastback
using Dates
using DataFrames

const ENTRY_DT = Date(2026, 1, 5)
const MARK_DT = Date(2026, 1, 12)
const EXPIRY_DT = Date(2026, 1, 17)

function spread_account(capital)
    acc = Account(;
        time_type=Date,
        funding=AccountFunding.Margined,
        base_currency=CashSpec(:USD),
        broker=NoOpBroker(),
    )
    usd = cash_asset(acc, :USD)
    deposit!(acc, :USD, capital)

    long_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C100"), :AAPL, :USD;
        strike=100.0,
        expiry=EXPIRY_DT,
        right=OptionRight.Call,
        time_type=Date,
    ))
    short_call = register_instrument!(acc, option_instrument(Symbol("AAPL_20260117_C105"), :AAPL, :USD;
        strike=105.0,
        expiry=EXPIRY_DT,
        right=OptionRight.Call,
        time_type=Date,
    ))

    acc, usd, long_call, short_call
end

function snapshot(acc, usd)
    DataFrame(
        metric=[
            "cash",
            "equity",
            "initial margin",
            "available funds",
        ],
        value=[
            round(cash_balance(acc, usd); digits=2),
            round(equity(acc, usd); digits=2),
            round(init_margin_used(acc, usd); digits=2),
            round(available_funds(acc, usd); digits=2),
        ],
    )
end

#---------------------------------------------------------

# ### Why single-leg execution is not enough

single_acc, single_usd, single_long, _ = spread_account(300.0);

single_leg_requirement = 5.0 * single_long.spec.multiplier;

DataFrame(
    metric=["available funds", "single-leg long call requirement"],
    value=[
        available_funds(single_acc, single_usd),
        single_leg_requirement,
    ],
)

# The long option alone needs more buying power than the account has. The full
# debit spread, however, has only 300 of terminal risk.

snapshot(single_acc, single_usd)

#---------------------------------------------------------

# ### The complete debit spread can be filled atomically

acc, usd, long_call, short_call = spread_account(300.0);

orders = [
    Order(oid!(acc), long_call, ENTRY_DT, 5.0, 1.0),
    Order(oid!(acc), short_call, ENTRY_DT, 2.0, -1.0),
];

trades = fill_option_strategy!(
    acc,
    orders;
    dt=ENTRY_DT,
    fill_prices=[5.0, 2.0],
    bids=[5.0, 2.0],
    asks=[5.0, 2.0],
    lasts=[5.0, 2.0],
    underlying_price=100.0,
);

(length(trades), eltype(trades))

# The spread is now open with zero remaining available funds: the account has
# exactly enough capital for the final 300 maximum loss.

snapshot(acc, usd)

DataFrame(positions_table(acc))

#---------------------------------------------------------

# ### Mark the spread before expiry

process_step!(
    acc,
    MARK_DT;
    option_underlyings=[OptionUnderlyingUpdate(long_call, 103.0)],
    marks=[
        MarkUpdate(long_call.index, 7.20, 7.20, 7.20),
        MarkUpdate(short_call.index, 3.00, 3.00, 3.00),
    ],
    expiries=false,
);

snapshot(acc, usd)

#---------------------------------------------------------

# ### Cash-settle at expiry

process_step!(
    acc,
    EXPIRY_DT;
    option_underlyings=[OptionUnderlyingUpdate(long_call, 106.0)],
    expiries=true,
);

snapshot(acc, usd)

DataFrame(trades_table(acc))[:, [:trade_date, :symbol, :side, :fill_price, :fill_qty, :cash_delta_settle, :reason]]
