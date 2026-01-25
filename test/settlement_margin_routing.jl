using Dates
using TestItemRunner

@testitem "Settlement cashflows routed to settlement currency" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD, margining_style=MarginingStyle.BaseCurrency)
    register_cash_asset!(acc, Cash(:USD))
    register_cash_asset!(acc, Cash(:EUR))
    deposit!(acc, cash_asset(acc, :USD), 10_000.0)

    inst = Instrument(Symbol("BTC/EUR_SETL_USD"), :BTC, :EUR;
        settle_symbol=:USD,
        margin_symbol=:USD,
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_maint_long=0.05,
        multiplier=1.0,
    )

    register_instrument!(acc, inst)

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 20_000.0, 1.0)
    trade = fill_order!(acc, order, dt, order.price)
    @test trade isa Trade

    usd_idx = cash_asset(acc, :USD).index
    eur_idx = cash_asset(acc, :EUR).index

    # No settlement movement on entry for VM
    @test acc.balances[usd_idx] == 10_000.0
    @test acc.balances[eur_idx] == 0.0

    # VM P&L goes to settlement currency
    update_pnl!(acc, inst, 21_000.0, 21_000.0)
    @test acc.balances[usd_idx] ≈ 11_000.0 atol=1e-8
    @test acc.balances[eur_idx] == 0.0

    # Funding also routes to settlement currency
    apply_funding!(acc, inst, dt + Day(1); funding_rate=0.01, mark_price=21_000.0)
    @test acc.balances[usd_idx] ≈ 11_000.0 - 210.0 atol=1e-8
    @test acc.balances[eur_idx] == 0.0
end

@testitem "Margin requirement recorded in margin currency when different from settlement" begin
    using Test, Fastback, Dates

    acc = Account(; mode=AccountMode.Margin, base_currency=:USD, margining_style=MarginingStyle.PerCurrency)
    register_cash_asset!(acc, Cash(:USD))
    register_cash_asset!(acc, Cash(:EUR))
    deposit!(acc, cash_asset(acc, :USD), 5_000.0)

    inst = Instrument(Symbol("DERIV/EUR-MUSD"), :BTC, :EUR;
        settle_symbol=:EUR,
        margin_symbol=:USD,
        contract_kind=ContractKind.Future,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_maint_long=0.05,
        expiry=DateTime(2026, 1, 10),
    )

    register_instrument!(acc, inst)

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 20_000.0, 0.1)
    trade = fill_order!(acc, order, dt, order.price)
    @test trade isa Trade

    usd_idx = cash_asset(acc, :USD).index
    eur_idx = cash_asset(acc, :EUR).index

    @test acc.init_margin_used[usd_idx] > 0
    @test acc.init_margin_used[eur_idx] == 0
    @test acc.maint_margin_used[usd_idx] > 0
    @test acc.maint_margin_used[eur_idx] == 0
end

@testitem "FX conversion applied to settlement and margin currencies" begin
    using Test, Fastback, Dates

    er = SpotExchangeRates()
    acc = Account(; mode=AccountMode.Margin, base_currency=:USD, margining_style=MarginingStyle.BaseCurrency, exchange_rates=er)
    register_cash_asset!(acc, Cash(:USD))
    register_cash_asset!(acc, Cash(:EUR))
    # Set EURUSD = 1.1
    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.1)

    deposit!(acc, cash_asset(acc, :USD), 10_000.0)

    inst = Instrument(Symbol("BTC/EUR_SETL_USD_MUSD"), :BTC, :EUR;
        settle_symbol=:USD,
        margin_symbol=:USD,
        contract_kind=ContractKind.Perpetual,
        settlement=SettlementStyle.VariationMargin,
        margin_mode=MarginMode.PercentNotional,
        margin_init_long=0.1,
        margin_maint_long=0.05,
        multiplier=1.0,
    )

    register_instrument!(acc, inst)

    dt = DateTime(2026, 1, 1)
    order = Order(oid!(acc), inst, dt, 20_000.0, 1.0)
    trade = fill_order!(acc, order, dt, order.price)
    @test trade isa Trade

    usd_idx = cash_asset(acc, :USD).index
    eur_idx = cash_asset(acc, :EUR).index

    # Initial VM cash impact zero; margin should be in USD with FX applied
    @test acc.balances[usd_idx] == 10_000.0
    @test acc.init_margin_used[usd_idx] ≈ 20_000.0 * 0.1 * 1.1 atol=1e-8

    # Mark up by 1000 EUR => 1100 USD to settlement
    update_pnl!(acc, inst, 21_000.0, 21_000.0)
    @test acc.balances[usd_idx] ≈ 11_100.0 atol=1e-8
    @test acc.balances[eur_idx] == 0.0
end
