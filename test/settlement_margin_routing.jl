using Dates
using TestItemRunner

@testitem "Settlement cashflows routed to settlement currency" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), mode=AccountMode.Margin, base_currency=base_currency, margining_style=MarginingStyle.BaseCurrency, exchange_rates=er)
    register_cash_asset!(acc, CashSpec(:EUR))
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.0)
    deposit!(acc, :USD, 10_000.0)

    inst = Instrument(Symbol("BTC/EUR_SETL_USD"), :BTC, :EUR;
        settle_symbol=:USD,
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        multiplier=1.0,
    )

    register_instrument!(acc, inst)

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 20_000.0, 1.0)
    trade = fill_order!(acc, order; dt=dt, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)
    @test trade isa Trade

    usd_idx = cash_asset(acc, :USD).index
    eur_idx = cash_asset(acc, :EUR).index

    # No settlement movement on entry for VM
    @test acc.ledger.balances[usd_idx] == 10_000.0
    @test acc.ledger.balances[eur_idx] == 0.0

    # VM P&L goes to settlement currency
    update_marks!(acc, inst, dt, 21_000.0, 21_000.0, 21_000.0)
    @test acc.ledger.balances[usd_idx] ≈ 11_000.0 atol=1e-8
    @test acc.ledger.balances[eur_idx] == 0.0

    # Funding also routes to settlement currency
    apply_funding!(acc, inst, dt + Day(1); funding_rate=0.01)
    @test acc.ledger.balances[usd_idx] ≈ 11_000.0 - 210.0 atol=1e-8
    @test acc.ledger.balances[eur_idx] == 0.0
end

@testitem "Variation margin settlements recorded as cashflows" begin
    using Test, Fastback, Dates

    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), mode=AccountMode.Margin, base_currency=base_currency)
    deposit!(acc, :USD, 10_000.0)

    inst = register_instrument!(
        acc,
        Instrument(
            Symbol("VM/USD"),
            :VM,
            :USD;
            contract_kind=ContractKind.Perpetual,
            settlement=SettlementStyle.VariationMargin,
            margin_mode=MarginMode.PercentNotional,
            margin_init_long=0.1,
            margin_init_short=0.1,
            margin_maint_long=0.05,
            margin_maint_short=0.05,
            multiplier=1.0,
        ),
    )

    dt0 = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt0, 100.0, 1.0)
    fill_order!(acc, order; dt=dt0, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)

    usd_idx = cash_asset(acc, :USD).index
    @test isempty(acc.cashflows)

    bal_before_up = acc.ledger.balances[usd_idx]
    update_marks!(acc, inst, dt0 + Hour(1), 109.0, 111.0, 110.0) # mark at mid=110
    cf1 = only(acc.cashflows)
    @test cf1.kind == CashflowKind.VariationMargin
    @test cf1.cash_index == usd_idx
    @test cf1.inst_index == inst.index
    @test cf1.amount ≈ 10.0 atol=1e-8
    @test acc.ledger.balances[usd_idx] - bal_before_up ≈ cf1.amount atol=1e-8
    @test get_position(acc, inst).pnl_quote == 0.0

    bal_before_down = acc.ledger.balances[usd_idx]
    update_marks!(acc, inst, dt0 + Hour(2), 95.0, 105.0, 100.0) # mid=100, settle loss
    @test length(acc.cashflows) == 2
    cf2 = acc.cashflows[end]
    @test cf2.kind == CashflowKind.VariationMargin
    @test cf2.amount ≈ -10.0 atol=1e-8
    @test acc.ledger.balances[usd_idx] - bal_before_down ≈ cf2.amount atol=1e-8
    pos = get_position(acc, inst)
    @test pos.pnl_quote == 0.0
    @test pos.avg_settle_price ≈ 100.0 atol=1e-8
end

@testitem "Margin requirement recorded in margin currency" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), mode=AccountMode.Margin, base_currency=base_currency, margining_style=MarginingStyle.BaseCurrency, exchange_rates=er)
    register_cash_asset!(acc, CashSpec(:EUR))
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.0)
    deposit!(acc, :USD, 5_000.0)

    inst = Instrument(Symbol("DERIV/EUR-MEUR"), :BTC, :EUR;
        settle_symbol=:EUR,
        contract_kind=ContractKind.Future,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        expiry=DateTime(2026, 1, 10),
    )

    register_instrument!(acc, inst)

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 20_000.0, 0.1)
    trade = fill_order!(acc, order; dt=dt, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)
    @test trade isa Trade

    usd_idx = cash_asset(acc, :USD).index
    eur_idx = cash_asset(acc, :EUR).index

    # Margin is recorded in margin currency (EUR), not USD
    @test acc.ledger.init_margin_used[eur_idx] > 0
    @test acc.ledger.init_margin_used[usd_idx] == 0
    @test acc.ledger.maint_margin_used[eur_idx] > 0
    @test acc.ledger.maint_margin_used[usd_idx] == 0
end

@testitem "Margin requirement routed to explicit margin currency" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), mode=AccountMode.Margin, base_currency=base_currency, margining_style=MarginingStyle.BaseCurrency, exchange_rates=er)
    register_cash_asset!(acc, CashSpec(:EUR))
    deposit!(acc, :USD, 10_000.0)

    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.1) # EUR -> USD

    inst = Instrument(Symbol("MARGIN/EUR"), :MARG, :USD;
        settle_symbol=:USD,
        margin_symbol=:EUR,
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        multiplier=1.0,
    )

    register_instrument!(acc, inst)

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 100.0, 1.0)
    trade = fill_order!(acc, order; dt=dt, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)
    @test trade isa Trade

    eur_idx = cash_asset(acc, :EUR).index
    usd_idx = cash_asset(acc, :USD).index

    expected_margin_eur = 100.0 * 0.1 * (1.0 / 1.1)
    @test inst.margin_cash_index == eur_idx
    @test acc.ledger.init_margin_used[eur_idx] ≈ expected_margin_eur atol=1e-8
    @test acc.ledger.init_margin_used[usd_idx] == 0.0
    @test init_margin_used_base_ccy(acc) ≈ expected_margin_eur * 1.1 atol=1e-8
end

@testitem "Per-currency fill rejects immediate settlement-currency deficit when margin currency differs" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(; mode=AccountMode.Margin, base_currency=base_currency, margining_style=MarginingStyle.PerCurrency, exchange_rates=er, broker=FlatFeeBroker(fixed=50.0))
    register_cash_asset!(acc, CashSpec(:EUR))
    deposit!(acc, :USD, 0.0)
    deposit!(acc, :EUR, 1_000.0)
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.1) # EUR -> USD

    inst = Instrument(Symbol("PCUR/SETTLEDEF"), :PCUR, :USD;
        settle_symbol=:USD,
        margin_symbol=:EUR,
        contract_kind=ContractKind.Spot,
        settlement=SettlementStyle.Asset,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=1.0,
        margin_maint_long=0.5,
        margin_init_short=1.0,
        margin_maint_short=0.5,
        multiplier=1.0,
    )
    register_instrument!(acc, inst)

    # Notional 11*100=1100 USD -> 1000 EUR margin requirement, fully covered by EUR equity.
    # But 50 USD commission would push USD post-fill equity below zero.
    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 100.0, 11.0)
    err = try
        fill_order!(acc, order; dt=dt, fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
        nothing
    catch e
        e
    end

    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin
    @test isempty(acc.trades)
    @test cash_balance(acc, cash_asset(acc, :USD)) == 0.0
    @test cash_balance(acc, cash_asset(acc, :EUR)) == 1_000.0
    @test init_margin_used(acc, cash_asset(acc, :USD)) == 0.0
    @test init_margin_used(acc, cash_asset(acc, :EUR)) == 0.0
end

@testitem "FX conversion applied to settlement currency" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), mode=AccountMode.Margin, base_currency=base_currency, margining_style=MarginingStyle.BaseCurrency, exchange_rates=er)
    register_cash_asset!(acc, CashSpec(:EUR))
    # Set EURUSD = 1.1
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.1)

    deposit!(acc, :USD, 10_000.0)

    inst = Instrument(Symbol("BTC/EUR_SETL_USD_MUSD"), :BTC, :EUR;
        settle_symbol=:USD,
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_init_short=0.1,
        margin_maint_long=0.05,
        margin_maint_short=0.05,
        multiplier=1.0,
    )

    register_instrument!(acc, inst)

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 20_000.0, 1.0)
    trade = fill_order!(acc, order; dt=dt, fill_price=order.price, bid=order.price, ask=order.price, last=order.price)
    @test trade isa Trade

    usd_idx = cash_asset(acc, :USD).index
    eur_idx = cash_asset(acc, :EUR).index

    # Initial VM cash impact zero; margin should be in USD (margin currency) with FX applied
    @test acc.ledger.balances[usd_idx] == 10_000.0
    @test acc.ledger.init_margin_used[usd_idx] ≈ 20_000.0 * 0.1 * 1.1 atol=1e-8

    # Mark up by 1000 EUR => 1100 USD to settlement
    update_marks!(acc, inst, dt, 21_000.0, 21_000.0, 21_000.0)
    @test acc.ledger.balances[usd_idx] ≈ 11_100.0 atol=1e-8
    @test acc.ledger.balances[eur_idx] == 0.0
end
