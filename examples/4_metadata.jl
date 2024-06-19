# # Attach metadata to instruments and orders
# 
# This example, based on *Random trading strategy example*, demonstrates
# how to add metadata to instruments and orders. This is useful for
# attaching additional information to instruments and orders, such as
# instrument names, descriptions, or custom attributes, e.g. for storing the
# signal, strategy, or model that generated the order.
#
# The type of the metadata can be arbitrarily defined by the user,
# and is typesafe for best performance.
#
# The `Account` type has the following three type parameters:
# - `OData`: Order metadata type
# - `IData`: Instrument metadata type
# - `CData`: Cash metadata type
#
# by default, these are set to `Nothing`, but can be customized to any type.
# 
# In this example, we define custom types `OData` for order metadata,
# and `IData` for instrument metadata.
# The order metadata type `OData` has a single field `probability::Float64`,
# and the instrument metadata type `IData` has a single field `full_name::String`.

using Fastback
using Dates
using Random
using Printf

## set RNG seed for reproducibility
Random.seed!(42);

## metadata type for orders
struct OData
    probability::Float64
end

function Base.show(io::IO, o::OData)
    print(io, @sprintf("probability=%.2f", o.probability))
end

## metadata type for instruments
struct IData
    full_name::String
end

function Base.show(io::IO, o::IData)
    print(io, "full_name=$(o.full_name)")
end

## generate synthetic price series
N = 2_000;
prices = 1000.0 .+ cumsum(randn(N) .+ 0.1);
dts = map(x -> DateTime(2020, 1, 1) + Hour(x), 0:N-1);

## create trading account with $10'000 start capital
acc = Account(; odata=OData, idata=IData);
add_cash!(acc, Cash(:USD), 10_000.0);

## register a dummy instrument
DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD;
    metadata=IData("Dummy instrument name")));

## data collector for account equity and drawdowns (sampling every hour)
collect_equity, equity_data = periodic_collector(Float64, Hour(1));
collect_drawdown, drawdown_data = drawdown_collector(DrawdownMode.Percentage, Hour(1));

## loop over price series
for (dt, price) in zip(dts, prices)
    ## randomly trade with 1% probability
    if rand() < 0.01
        prob = rand()
        quantity = prob > 0.4 ? 1.0 : -1.0
        order = Order(oid!(acc), DUMMY, dt, price, quantity; metadata=OData(prob))
        fill_order!(acc, order, dt, price; fill_qty=0.75order.quantity, commission_pct=0.001)
    end

    ## update position and account P&L
    update_pnl!(acc, DUMMY, price)

    ## collect data for plotting
    if should_collect(equity_data, dt)
        equity_value = equity(acc, :USD)
        collect_equity(dt, equity_value)
        collect_drawdown(dt, equity_value)
    end
end

#---------------------------------------------------------

# ### Print instrument incl. metadata to console

# Note that at the end, `metadata` is printed
# based on the `show` method defined above for `IData` type.

show(DUMMY)

#---------------------------------------------------------

# ### Print account summary incl. metadata to console

# Note that at the end of the **Trades** table, a **Metadata** column is shown
# based on the `show` method defined above for `OData` type.

show(acc)
