using TestItemRunner

@testitem "Cross-currency margin aggregation allows USD-funded EUR position" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency, exchange_rates=er)

    deposit!(acc, :USD, 1_000.0)
    register_cash_asset!(acc, CashSpec(:EUR))
    deposit!(acc, :EUR, 0.0) # register EUR quote ccy

    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.07)

    inst = register_instrument!(acc, Instrument(
        Symbol("EURSPOT/EUR"),
        :EURSPOT,
        :EUR;
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))

    trade = fill_order!(acc, Order(oid!(acc), inst, DateTime(2024, 1, 1), 100.0, 10.0); dt=DateTime(2024, 1, 1), fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
    @test trade isa Trade
    @test cash_balance(acc, cash_asset(acc, :EUR)) ≈ -1_000.0
    @test equity(acc, cash_asset(acc, :EUR)) ≈ 0.0
    @test init_margin_used_base_ccy(acc) ≈ 500.0 * 1.07 atol = 1e-8
end

@testitem "Cross-currency margin aggregation rejects when base equity insufficient" begin
    using Test, Fastback, Dates

    er = ExchangeRates()
    base_currency=CashSpec(:USD)
    acc = Account(; broker=NoOpBroker(), funding=AccountFunding.Margined, base_currency=base_currency, exchange_rates=er)

    deposit!(acc, :USD, 400.0)
    register_cash_asset!(acc, CashSpec(:EUR))
    deposit!(acc, :EUR, 0.0)

    update_rate!(er, cash_asset(acc, :EUR), cash_asset(acc, :USD), 1.07)

    inst = register_instrument!(acc, Instrument(
        Symbol("EURSPOT/EUR"),
        :EURSPOT,
        :EUR;
        settlement=SettlementStyle.PrincipalExchange,
        margin_requirement=MarginRequirement.PercentNotional,
        margin_init_long=0.5,
        margin_init_short=0.5,
        margin_maint_long=0.25,
        margin_maint_short=0.25,
    ))

    err = try
        fill_order!(acc, Order(oid!(acc), inst, DateTime(2024, 1, 1), 100.0, 10.0); dt=DateTime(2024, 1, 1), fill_price=100.0, bid=100.0, ask=100.0, last=100.0)
        nothing
    catch e
        e
    end
    @test err isa OrderRejectError
    @test err.reason == OrderRejectReason.InsufficientInitialMargin
end
