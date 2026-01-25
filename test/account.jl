using Dates
using TestItemRunner

@testitem "Account initializes cashflows ledger" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 0.0)

    @test isempty(acc.cashflows)
    @test acc.cashflow_sequence == 0
    @test cfid!(acc) == 1
    @test acc.cashflow_sequence == 1
end

@testitem "Order creation uses only time type parameter" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 1_000.0)
    inst = register_instrument!(acc, Instrument(Symbol("META/USD"), :META, :USD; margin_mode=MarginMode.PercentNotional))

    dt = DateTime(2025, 1, 1)
    order = Order{DateTime}(oid!(acc), inst, dt, 10.0, 1.0)

    @test order isa Order{DateTime}

    trade = fill_order!(acc, order, dt, 10.0)
    @test trade.order === order
    @test acc.trades[end] === trade
end

@testitem "Instrument requires quote cash asset" begin
    using Test, Fastback

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)

    # register a different cash asset to ensure missing quote currency is detected
    deposit!(acc, Cash(:EUR), 100.0)

    inst = Instrument(Symbol("MISS/USD"), :MISS, :USD; margin_mode=MarginMode.PercentNotional)
    @test_throws ArgumentError register_instrument!(acc, inst)

    # once the quote cash asset is registered, the instrument should register successfully
    deposit!(acc, Cash(:USD), 0.0)
    inst2 = Instrument(Symbol("MISS/USD"), :MISS, :USD; margin_mode=MarginMode.PercentNotional)
    registered = register_instrument!(acc, inst2)
    @test registered === inst2
    @test get_position(acc, inst2).inst === inst2
end

@testitem "Account long order w/o commission" begin
    using Test, Fastback, Dates
    # create trading account
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 100_000.0)

    @test cash_balance(acc, :USD) == 100_000.0
    @test equity(acc, :USD) == 100_000.0
    @test length(acc.cash) == 1
    # create instrument
    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD; margin_mode=MarginMode.PercentNotional))
    pos = get_position(acc, DUMMY)
    # generate data
    dates = collect(DateTime(2018, 1, 2):Day(1):DateTime(2018, 1, 4))
    prices = [100.0, 100.5, 102.5]
    # buy order
    qty = 100.0
    order = Order(oid!(acc), DUMMY, dates[1], prices[1], qty)
    exe1 = fill_order!(acc, order, dates[1], prices[1])
    @test exe1 == acc.trades[end]
    @test exe1.commission == 0.0
    @test nominal_value(exe1) == qty * prices[1]
    @test exe1.realized_pnl == 0.0
    # @test realized_return(exe1) == 0.0
    @test pos.avg_entry_price == 100.0
    @test pos.avg_settle_price == 100.0
    # update position and account P&L
    update_marks!(acc, pos; dt=dates[2], close_price=prices[2])
    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ (prices[2] - prices[1]) * pos.quantity
    @test cash_balance(acc, :USD) ≈ 100_000.0
    @test equity(acc, :USD) ≈ 100_000.0 + (prices[2] - prices[1]) * pos.quantity
    # close position
    order = Order(oid!(acc), DUMMY, dates[3], prices[3], -pos.quantity)
    fill_order!(acc, order, dates[3], prices[3])
    # update position and account P&L
    update_marks!(acc, pos; dt=dates[3], close_price=prices[3])
    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ 0
    @test cash_balance(acc, :USD) ≈ 100_000.0 + (prices[3] - prices[1]) * qty
    @test equity(acc, :USD) ≈ cash_balance(acc, :USD)
    show(acc)
end

@testitem "Deposit & withdraw cash" begin
    using Test, Fastback

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    usd = Cash(:USD)

    deposit!(acc, usd, 1_000.0)
    @test cash_balance(acc, usd) == 1_000.0
    @test equity(acc, usd) == 1_000.0

    withdraw!(acc, usd, 400.0)
    @test cash_balance(acc, usd) == 600.0
    @test equity(acc, usd) == 600.0
    @test isempty(acc.cashflows)
end

@testitem "Account long order w/ commission ccy" begin
    using Test, Fastback, Dates
    # create trading account
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 100_000.0)

    @test cash_balance(acc, :USD) == 100_000.0
    @test equity(acc, :USD) == 100_000.0
    @test length(acc.cash) == 1
    # create instrument
    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD; margin_mode=MarginMode.PercentNotional))
    pos = get_position(acc, DUMMY)
    # generate data
    dates = collect(DateTime(2018, 1, 2):Day(1):DateTime(2018, 1, 4))
    prices = [100.0, 100.5, 102.5]
    # buy order
    qty = 100.0
    order = Order(oid!(acc), DUMMY, dates[1], prices[1], qty)
    commission = 1.0
    exe1 = fill_order!(acc, order, dates[1], prices[1]; commission=commission)
    @test exe1 == acc.trades[end]
    @test nominal_value(exe1) == qty * prices[1]
    @test exe1.commission == commission
    @test exe1.realized_pnl == -commission
    # @test realized_return(exe1) == 0.0
    @test pos.avg_entry_price == 100.0
    @test pos.avg_settle_price == 100.0
    # update position and account P&L
    update_marks!(acc, pos; dt=dates[2], close_price=prices[2])

    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ (prices[2] - prices[1]) * pos.quantity # does not include commission!
    @test cash_balance(acc, :USD) ≈ 100_000.0 - commission
    @test equity(acc, :USD) ≈ 100_000.0+ (prices[2] - prices[1]) * pos.quantity - commission
    # close position
    order = Order(oid!(acc), DUMMY, dates[3], prices[3], -pos.quantity)
    exe2 = fill_order!(acc, order, dates[3], prices[3]; commission=0.5)
    # update position and account P&L
    update_marks!(acc, pos; dt=dates[3], close_price=prices[3])
    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ 0
    @test cash_balance(acc, :USD) ≈ 100_000.0 + (prices[3] - prices[1]) * qty - commission - 0.5
    @test equity(acc, :USD) ≈ cash_balance(acc, :USD)
    show(acc)
end

@testitem "Account long order w/ commission pct" begin
    using Test, Fastback, Dates
    # create trading account
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD);
    deposit!(acc, Cash(:USD), 100_000.0)
    @test cash_balance(acc, :USD) == 100_000.0
    @test equity(acc, :USD) == 100_000.0
    @test length(acc.cash) == 1
    # create instrument
    DUMMY = register_instrument!(acc, Instrument(Symbol("DUMMY/USD"), :DUMMY, :USD; margin_mode=MarginMode.PercentNotional))
    pos = get_position(acc, DUMMY)
    # generate data
    dates = collect(DateTime(2018, 1, 2):Day(1):DateTime(2018, 1, 4))
    prices = [100.0, 100.5, 102.5]
    # buy order
    qty = 100.0
    order = Order(oid!(acc), DUMMY, dates[1], prices[1], qty)
    commission_pct1 = 0.001
    exe1 = fill_order!(acc, order, dates[1], prices[1]; commission_pct=commission_pct1)
    @test nominal_value(exe1) == qty * prices[1]
    @test exe1.commission == commission_pct1*nominal_value(exe1)
    @test acc.trades[end].realized_pnl == -commission_pct1*nominal_value(exe1)
    # @test realized_return(acc.trades[end]) == 0.0
    @test pos.avg_entry_price == 100.0
    @test pos.avg_settle_price == 100.0
    # update position and account P&L
    update_marks!(acc, pos; dt=dates[2], close_price=prices[2])

    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ (prices[2] - prices[1]) * pos.quantity # does not include commission!
    @test cash_balance(acc, :USD) ≈ 100_000.0 - exe1.commission
    @test equity(acc, :USD) ≈ 100_000.0+ (prices[2] - prices[1]) * pos.quantity - exe1.commission
    # close position
    order = Order(oid!(acc), DUMMY, dates[3], prices[3], -pos.quantity)
    exe2 = fill_order!(acc, order, dates[3], prices[3]; commission_pct=0.0005)
    # update position and account P&L
    update_marks!(acc, pos; dt=dates[3], close_price=prices[3])
    @test pos.value_local == pos.pnl_local
    @test pos.pnl_local ≈ 0
    @test cash_balance(acc, :USD) ≈ 100_000.0 + (prices[3] - prices[1]) * qty - exe1.commission - exe2.commission
    @test equity(acc, :USD) ≈ cash_balance(acc, :USD)
    show(acc)
end

@testitem "Commission pct uses instrument multiplier" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 100_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("MULTI/USD"), :MULTI, :USD; multiplier=10.0, margin_mode=MarginMode.PercentNotional))

    dates = collect(DateTime(2018, 1, 2):Day(1):DateTime(2018, 1, 3))
    price = 100.0
    qty = 2.0
    order = Order(oid!(acc), inst, dates[1], price, qty)
    commission_pct = 0.001
    trade = fill_order!(acc, order, dates[1], price; commission_pct=commission_pct)

    expected_nominal = qty * price * inst.multiplier
    @test nominal_value(order) == expected_nominal
    @test nominal_value(trade) == expected_nominal
    @test trade.commission == commission_pct * expected_nominal
end

@testitem "Spot long asset-settled valuation" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOT/USD"),
        :SPOT,
        :USD;
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))
    pos = get_position(acc, inst)

    dt = DateTime(2021, 1, 1)
    price = 50.0
    qty = 100.0
    order = Order(oid!(acc), inst, dt, price, qty)
    fill_order!(acc, order, dt, price)

    @test cash_balance(acc, :USD) ≈ 5_000.0
    @test pos.value_local ≈ 5_000.0
    @test equity(acc, :USD) ≈ 10_000.0

    update_marks!(acc, pos; dt=dt, close_price=60.0)
    @test pos.value_local ≈ 6_000.0
    @test equity(acc, :USD) ≈ 11_000.0
end

@testitem "Spot short asset-settled valuation" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("SPOT/USD"),
        :SPOT,
        :USD;
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))
    pos = get_position(acc, inst)

    dt = DateTime(2021, 1, 1)
    price = 50.0
    qty = -100.0
    order = Order(oid!(acc), inst, dt, price, qty)
    fill_order!(acc, order, dt, price)

    @test cash_balance(acc, :USD) ≈ 15_000.0
    @test pos.value_local ≈ -5_000.0
    @test equity(acc, :USD) ≈ 10_000.0

    update_marks!(acc, pos; dt=dt, close_price=60.0)
    @test pos.value_local ≈ -6_000.0
    @test equity(acc, :USD) ≈ 9_000.0
end

@testitem "Variation margin settles P&L into cash" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("FUT/USD"),
        :FUT,
        :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))
    pos = get_position(acc, inst)

    dt = DateTime(2021, 1, 1)
    price = 50.0
    qty = 100.0
    order = Order(oid!(acc), inst, dt, price, qty)
    fill_order!(acc, order, dt, price)

    @test cash_balance(acc, :USD) ≈ 10_000.0
    @test equity(acc, :USD) ≈ 10_000.0
    @test pos.value_local ≈ 0.0
    @test pos.pnl_local ≈ 0.0
    @test pos.avg_entry_price ≈ price
    @test pos.avg_settle_price ≈ price

    update_marks!(acc, pos; dt=dt, close_price=60.0)
    @test cash_balance(acc, :USD) ≈ 11_000.0
    @test equity(acc, :USD) ≈ 11_000.0
    @test pos.value_local ≈ 0.0
    @test pos.pnl_local ≈ 0.0
    @test pos.avg_entry_price ≈ price
    @test pos.avg_settle_price ≈ 60.0

    update_marks!(acc, pos; dt=dt, close_price=55.0)
    @test cash_balance(acc, :USD) ≈ 10_500.0
    @test equity(acc, :USD) ≈ 10_500.0
    @test pos.avg_entry_price ≈ price
    @test pos.avg_settle_price ≈ 55.0

    order = Order(oid!(acc), inst, dt, 55.0, -qty)
    fill_order!(acc, order, dt, 55.0)

    @test pos.quantity ≈ 0.0
    @test cash_balance(acc, :USD) ≈ 10_500.0
    @test equity(acc, :USD) ≈ 10_500.0
    @test pos.avg_entry_price == 0.0
    @test pos.avg_settle_price == 0.0
end

@testitem "Variation margin marks to fill before realizing pnl" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("VMARK/USD"),
        :VMARK,
        :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
    ))
    pos = get_position(acc, inst)

    dt_open = DateTime(2026, 1, 1)
    open_price = 100.0
    qty = 10.0
    order_open = Order(oid!(acc), inst, dt_open, open_price, qty)
    fill_order!(acc, order_open, dt_open, open_price)

    close_price = 110.0
    reduce_qty = -5.0
    dt_close = dt_open + Day(1)
    order_close = Order(oid!(acc), inst, dt_close, close_price, reduce_qty)
    trade = fill_order!(acc, order_close, dt_close, close_price)

    @test trade.realized_pnl ≈ (close_price - open_price) * abs(reduce_qty)
    @test pos.quantity ≈ qty + reduce_qty
    @test pos.avg_entry_price ≈ open_price
    @test pos.avg_settle_price ≈ close_price
    @test cash_balance(acc, :USD) ≈ 10_000.0 + (close_price - open_price) * qty
    @test equity(acc, :USD) ≈ cash_balance(acc, :USD)
end

@testitem "Trading after expiry returns rejection" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    start_dt = DateTime(2026, 1, 1)
    expiry_dt = DateTime(2026, 2, 1)
    inst = register_instrument!(acc, Instrument(
        Symbol("EXP/USD"),
        :EXP,
        :USD;
        contract_kind=ContractKind.Future,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_maint_long=0.05,
        start_time=start_dt,
        expiry=expiry_dt,
    ))

    open_dt = start_dt + Day(1)
    order = Order(oid!(acc), inst, open_dt, 100.0, 1.0)
    fill_order!(acc, order, open_dt, 100.0)

    late_dt = expiry_dt + Day(1)
    late_order = Order(oid!(acc), inst, late_dt, 110.0, 1.0)
    rejection = fill_order!(acc, late_order, late_dt, 110.0)
    @test rejection == OrderRejectReason.InstrumentNotAllowed
end

@testitem "Cash account: buy too large is rejected" begin
    using Test, Fastback, Dates

    acc = Account(; base_currency=:USD)
    deposit!(acc, Cash(:USD), 100.0)

    inst = register_instrument!(acc, Instrument(Symbol("CASH/USD"), :CASH, :USD; settlement=SettlementStyle.Asset))
    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 200.0, 1.0)

    result = fill_order!(acc, order, dt, order.price)
    @test result == OrderRejectReason.InsufficientCash
    @test isempty(acc.trades)
    pos = get_position(acc, inst)
    @test pos.quantity == 0.0
    @test cash_balance(acc, :USD) == 100.0
end

@testitem "Cash account: short sell is rejected" begin
    using Test, Fastback, Dates

    acc = Account(; base_currency=:USD)
    deposit!(acc, Cash(:USD), 1_000.0)
    inst = register_instrument!(acc, Instrument(Symbol("SHORT/USD"), :SHORT, :USD; settlement=SettlementStyle.Asset))

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 10.0, -1.0)
    result = fill_order!(acc, order, dt, order.price)
    @test result == OrderRejectReason.ShortNotAllowed
    @test isempty(acc.trades)
    pos = get_position(acc, inst)
    @test pos.quantity == 0.0
end

@testitem "Cash account: sell within holdings works" begin
    using Test, Fastback, Dates

    acc = Account(; base_currency=:USD)
    deposit!(acc, Cash(:USD), 1_000.0)
    inst = register_instrument!(acc, Instrument(Symbol("CASHSELL/USD"), :CASHSELL, :USD; settlement=SettlementStyle.Asset))

    buy_dt = DateTime(2026, 1, 1)
    buy_order = Order(oid!(acc), inst, buy_dt, 10.0, 50.0)
    buy_trade = fill_order!(acc, buy_order, buy_dt, buy_order.price)
    @test buy_trade isa Trade

    sell_dt = buy_dt + Day(1)
    sell_order = Order(oid!(acc), inst, sell_dt, 12.0, -20.0)
    sell_trade = fill_order!(acc, sell_order, sell_dt, sell_order.price)
    @test sell_trade isa Trade

    pos = get_position(acc, inst)
    @test pos.quantity == 30.0
    @test pos.avg_entry_price ≈ 10.0
    @test pos.avg_settle_price ≈ 10.0
    @test cash_balance(acc, :USD) ≈ 740.0
    @test equity(acc, :USD) ≈ 1_100.0
end

@testitem "Cash account rejects margin instruments" begin
    using Test, Fastback, Dates

    acc = Account(; base_currency=:USD)
    deposit!(acc, Cash(:USD), 5_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("FUT/USD"),
        :FUT,
        :USD;
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_maint_long=0.05,
    ))

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 100.0, 1.0)
    result = fill_order!(acc, order, dt, order.price)

    @test result == OrderRejectReason.InstrumentNotAllowed
    @test isempty(acc.trades)
    pos = get_position(acc, inst)
    @test pos.quantity == 0.0
end

@testitem "Insufficient initial margin rejects fill" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 100.0)
    inst = register_instrument!(acc, Instrument(
        Symbol("MARGINFAIL/USD"),
        :MARGINFAIL,
        :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.2,
        margin_maint_long=0.1
    ))

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 1_000.0, 1.0)
    result = fill_order!(acc, order, dt, order.price)
    @test result == OrderRejectReason.InsufficientInitialMargin
    @test isempty(acc.trades)
    pos = get_position(acc, inst)
    @test pos.quantity == 0.0
end

@testitem "settle_expiry! closes positions and releases margin" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 20_000.0)

    start_dt = DateTime(2026, 1, 1)
    expiry_dt = DateTime(2026, 2, 1)
    inst = register_instrument!(acc, Instrument(
        Symbol("FUT/USD"),
        :FUT,
        :USD;
        contract_kind=ContractKind.Future,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_maint_long=0.05,
        start_time=start_dt,
        expiry=expiry_dt,
    ))
    pos = get_position(acc, inst)

    open_dt = start_dt + Day(10)
    qty = 3.0
    open_price = 100.0
    open_order = Order(oid!(acc), inst, open_dt, open_price, qty)
    fill_order!(acc, open_order, open_dt, open_price)

    usd_index = cash_asset(acc, :USD).index
    @test pos.quantity == qty
    @test pos.margin_init_local > 0.0
    @test acc.init_margin_used[usd_index] > 0.0

    settle_price = 105.0
    trade = settle_expiry!(acc, inst, expiry_dt; settle_price=settle_price)

    @test trade isa Trade
    @test acc.trades[end] === trade
    @test trade.fill_qty ≈ -qty
    @test pos.quantity == 0.0
    @test pos.margin_init_local == 0.0
    @test pos.margin_maint_local == 0.0
    @test acc.init_margin_used[usd_index] == 0.0
    @test acc.maint_margin_used[usd_index] == 0.0
end

@testitem "Margin disabled stays zero" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("NOMARGIN/USD"), :NOMARGIN, :USD; settlement=SettlementStyle.Asset))
    pos = get_position(acc, inst)

    dt = DateTime(2021, 1, 1)
    order = Order(oid!(acc), inst, dt, 100.0, 10.0)
    fill_order!(acc, order, dt, 100.0)
    update_marks!(acc, pos; dt=dt, close_price=101.0)

    usd_index = cash_asset(acc, :USD).index
    @test pos.margin_init_local == 0.0
    @test pos.margin_maint_local == 0.0
    @test acc.init_margin_used[usd_index] == 0.0
    @test acc.maint_margin_used[usd_index] == 0.0
end

@testitem "Margin percent notional updates with mark" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("MARGIN/USD"),
        :MARGIN,
        :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.2,
        margin_maint_long=0.05,
        margin_maint_short=0.1
    ))
    pos = get_position(acc, inst)

    dt = DateTime(2021, 1, 1)
    price = 100.0
    qty = 10.0
    order = Order(oid!(acc), inst, dt, price, qty)
    fill_order!(acc, order, dt, price)

    usd_index = cash_asset(acc, :USD).index
    @test pos.margin_init_local ≈ qty * price * 0.1
    @test pos.margin_maint_local ≈ qty * price * 0.05
    @test acc.init_margin_used[usd_index] ≈ qty * price * 0.1
    @test acc.maint_margin_used[usd_index] ≈ qty * price * 0.05

    update_marks!(acc, pos; dt=dt, close_price=120.0)
    @test pos.margin_init_local ≈ qty * 120.0 * 0.1
    @test pos.margin_maint_local ≈ qty * 120.0 * 0.05
    @test acc.init_margin_used[usd_index] ≈ qty * 120.0 * 0.1
    @test acc.maint_margin_used[usd_index] ≈ qty * 120.0 * 0.05
end

@testitem "Broker-style margin metrics" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    @test acc.mode == AccountMode.Margin
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("BROKER/USD"),
        :BROKER,
        :USD;
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_maint_long=0.05,
    ))
    pos = get_position(acc, inst)

    dt = DateTime(2025, 1, 1)
    price = 100.0
    qty = 5.0
    order = Order(oid!(acc), inst, dt, price, qty)
    fill_order!(acc, order, dt, price)

    usd = cash_asset(acc, :USD)
    expected_init = qty * price * 0.1
    expected_maint = qty * price * 0.05

    @test init_margin_used(acc, usd) ≈ expected_init
    @test init_margin_used(acc, :USD) ≈ expected_init
    @test maint_margin_used(acc, usd) ≈ expected_maint
    @test maint_margin_used(acc, :USD) ≈ expected_maint
    @test available_funds(acc, usd) ≈ equity(acc, usd) - expected_init
    @test excess_liquidity(acc, :USD) ≈ equity(acc, :USD) - expected_maint
end

@testitem "Margin fixed per contract uses per-contract rates" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD)
    deposit!(acc, Cash(:USD), 10_000.0)

    inst = register_instrument!(acc, Instrument(
        Symbol("FIXED/USD"),
        :FIXED,
        :USD;
        margin_mode=MarginMode.FixedPerContract,
        margin_init_long=100.0,
        margin_init_short=150.0,
        margin_maint_long=50.0,
        margin_maint_short=75.0
    ))
    pos = get_position(acc, inst)

    dt = DateTime(2021, 1, 1)
    price = 20.0
    qty = 2.0
    order = Order(oid!(acc), inst, dt, price, qty)
    fill_order!(acc, order, dt, price)

    usd_index = cash_asset(acc, :USD).index
    @test pos.margin_init_local ≈ qty * 100.0
    @test pos.margin_maint_local ≈ qty * 50.0
    @test acc.init_margin_used[usd_index] ≈ qty * 100.0
    @test acc.maint_margin_used[usd_index] ≈ qty * 50.0

    update_marks!(acc, pos; dt=dt, close_price=25.0)
    @test pos.margin_init_local ≈ qty * 100.0
    @test pos.margin_maint_local ≈ qty * 50.0
    @test acc.init_margin_used[usd_index] ≈ qty * 100.0
    @test acc.maint_margin_used[usd_index] ≈ qty * 50.0

    order2 = Order(oid!(acc), inst, dt, price, -3.0)
    fill_order!(acc, order2, dt, price)
    @test pos.quantity ≈ -1.0
    @test pos.margin_init_local ≈ 150.0
    @test pos.margin_maint_local ≈ 75.0
    @test acc.init_margin_used[usd_index] ≈ 150.0
    @test acc.maint_margin_used[usd_index] ≈ 75.0
end

@testitem "Fixed-per-contract margin uses settlement currency FX" begin
    using Test, Fastback, Dates

    er = SpotExchangeRates()
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD, exchange_rates=er)

    # Register settlement (EUR) and margin/base (USD)
    deposit!(acc, Cash(:USD), 10_000.0)
    deposit!(acc, Cash(:EUR), 0.0)
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.10) # EUR→USD

    inst = register_instrument!(acc, Instrument(
        Symbol("FIXED/EUR"),
        :FIXED,
        :EUR;
        settlement=SettlementStyle.Cash,     # settlement currency = EUR (and margin currency)
        margin_mode=MarginMode.FixedPerContract,
        margin_init_long=100.0,              # per-contract in settlement ccy (EUR)
        margin_init_short=120.0,
        margin_maint_long=50.0,
        margin_maint_short=60.0
    ))
    pos = get_position(acc, inst)

    dt = DateTime(2025, 1, 1)
    order = Order(oid!(acc), inst, dt, 10.0, 2.0) # qty=2 contracts
    fill_order!(acc, order, dt, 10.0)

    eur_idx = cash_asset(acc, :EUR).index
    @test pos.margin_init_local ≈ 2 * 100.0           # 200 EUR
    @test pos.margin_maint_local ≈ 2 * 50.0           # 100 EUR
    @test acc.init_margin_used[eur_idx] ≈ pos.margin_init_local
    @test acc.maint_margin_used[eur_idx] ≈ pos.margin_maint_local
    @test init_margin_used_base_ccy(acc) ≈ pos.margin_init_local * 1.10
end


@testitem "Account with Date timestamps" begin
    using Test, Fastback, Dates, Tables

    acc = Account(; mode=AccountMode.Margin, time_type=Date, date_format=dateformat"yyyy-mm-dd", base_currency=:USD)
    deposit!(acc, Cash(:USD), 1_000.0)

    inst = register_instrument!(acc, Instrument(Symbol("DATE/USD"), :DATE, :USD; time_type=Date, margin_mode=MarginMode.PercentNotional))

    d₁ = Date(2020, 1, 1)
    order₁ = Order(oid!(acc), inst, d₁, 10.0, 1.0)
    fill_order!(acc, order₁, d₁, 10.0)

    d₂ = Date(2020, 1, 2)
    order₂ = Order(oid!(acc), inst, d₂, 9.5, -1.0)
    fill_order!(acc, order₂, d₂, 9.5)

    @test all(t.date isa Date for t in acc.trades)

    tbl = trades_table(acc)
    schema = Tables.schema(tbl)
    @test schema.types[3] == Date
    rows = collect(Tables.rows(tbl))
    @test rows[1].trade_date isa Date
    @test rows[end].order_date == d₂
end


# @testset "Backtesting single ticker net long/short swap" begin
#     # create instrument
#     inst = Instrument(1, "TICKER")
#     insts = [inst]

#     # market data (order books)
#     data = MarketData(insts)

#     # order book for instrument
#     book = data.order_books[inst.index]

#     # create trading account
#     acc = Account(insts, 100_000.0)

#     # generate data
#     prices = [
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 0), 100.0, 101.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 1), 100.5, 102.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 2), 102.5, 103.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 3), 100.0, 100.5),
#     ]

#     pos = acc.positions[inst.index]

#     update_book!(book, prices[1])

#     execute_order!(acc, book, Order(inst, -100.0, prices[1].dt))
#     @test acc.positions[inst.index].avg_price == book.bba.bid

#     update_account!(acc, data, inst)

#     @test pos.pnl_local ≈ -100
#     @test total_balance(acc) ≈ 100_000.0 - pos.quantity * prices[1].bid
#     @test total_equity(acc) ≈ 99_900.0

#     update_book!(book, prices[2])
#     update_account!(acc, data, inst)

#     @test pos.pnl_local ≈ -200
#     @test total_balance(acc) ≈ 100_000.0 - pos.quantity * prices[1].bid
#     @test total_equity(acc) ≈ 99_800.0

#     update_book!(book, prices[3])
#     update_account!(acc, data, inst)

#     # open long order (results in net long +100)
#     execute_order!(acc, book, Order(inst, 200.0, prices[3].dt))

#     @test acc.positions[inst.index].avg_price == book.bba.ask
#     @test realized_return(acc.trades[end].execution) ≈ (100.0 - 103.0) / 100.0
#     @test realized_pnl(acc.trades[end].execution) ≈ -300.0
#     # @test calc_realized_return(acc.trades[end].execution) ≈ (100.0 - 103.0) / 100.0
#     @test acc.trades[end].execution.realized_pnl ≈ -300.0
#     @test pos.pnl_local ≈ -50
#     @test total_balance(acc) ≈ 100_000.0 + sum(t.execution.realized_pnl for t in acc.trades) - pos.quantity * prices[3].ask
#     @test total_equity(acc) ≈ 99_650.0

#     update_book!(book, prices[4])
#     update_account!(acc, data, inst)

#     @test total_equity(acc) ≈ 99_400.0

#     # open short order (results in net short -50)
#     execute_order!(acc, book, Order(inst, -150.0, prices[4].dt))

#     @test acc.positions[inst.index].avg_price == book.bba.bid
#     @test acc.trades[end].execution.realized_pnl ≈ -300.0
#     @test pos.pnl_local ≈ -25
#     @test total_balance(acc) ≈ 100_000.0 + sum(t.execution.realized_pnl for t in acc.trades) - pos.quantity * prices[4].bid
#     @test total_equity(acc) ≈ 99_375.0

#     # close open position
#     execute_order!(acc, book, Order(inst, 50.0, prices[4].dt))

#     @test total_balance(acc) ≈ 99_375.0
#     @test total_equity(acc) ≈ 99_375.0
#     @test acc.trades[end].execution.realized_pnl ≈ -25.0

#     @test pos.quantity == 0.0
#     @test pos.avg_price == 0.0
#     @test pos.pnl_local == 0.0
#     @test length(pos.trades) == 4

#     @test total_equity(acc) == 100_000.0+ sum(t.execution.realized_pnl for t in acc.trades)
#     @test total_balance(acc) == total_equity(acc)

#     # realized_orders = filter(t -> t.execution.realized_pnl != 0.0, acc.trades)
#     # @test equity_return(acc) ≈ sum(calc_realized_return(o)*o.execution.weight for o in realized_orders)
# end


# @testset "Backtesting single ticker avg_price" begin
#     # create instrument
#     inst = Instrument(1, "TICKER")
#     insts = [inst]

#     # market data (order books)
#     data = MarketData(insts)

#     # order book for instrument
#     book = data.order_books[inst.index]

#     # create trading account
#     acc = Account(insts, 100_000.0)

#     # generate data
#     prices = [
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 0), 100.0, 101.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 1), 100.5, 102.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 2), 102.5, 103.0),
#         BidAsk(DateTime(2018, 1, 2, 0, 0, 3), 100.0, 100.5),
#     ]

#     pos = acc.positions[inst.index]

#     update_book!(book, prices[1])
#     update_account!(acc, data, inst)

#     # buy order (net long +100)
#     execute_order!(acc, book, Order(inst, 100.0, prices[1].dt))
#     @test acc.positions[inst.index].avg_price == prices[1].ask

#     update_book!(book, prices[2])
#     update_account!(acc, data, inst)

#     # sell order (reduce exposure to net long +50)
#     execute_order!(acc, book, Order(inst, -50.0, prices[2].dt))
#     @test acc.positions[inst.index].avg_price == prices[1].ask

#     update_book!(book, prices[3])
#     update_account!(acc, data, inst)

#     # flip exposure (net short -50)
#     execute_order!(acc, book, Order(inst, -100.0, prices[3].dt))
#     @test acc.positions[inst.index].avg_price == prices[3].bid

#     update_book!(book, prices[4])
#     update_account!(acc, data, inst)

#     # close all positions
#     execute_order!(acc, book, Order(inst, 50.0, prices[4].dt))
#     @test acc.positions[inst.index].avg_price == 0.0
# end
