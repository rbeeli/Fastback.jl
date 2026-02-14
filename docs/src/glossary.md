# Glossary

## Account

`Account` is Fastback's central state object. It owns a `CashLedger` (`acc.ledger`) for cash assets, balances, equities, and margin vectors, plus open positions, executed trades, and order/trade sequence counters.

## Order

An `Order` encapsulates an instruction to trade an instrument at a specific time, price, and quantity, with optional `take_profit` and `stop_loss` levels. Orders translate into trades through `fill_order!`.

## Trade

A `Trade` records the actual execution of an order, including fill price, filled and remaining quantity, realized quantity, gross additive fill P&L in settlement currency (`fill_pnl_settle`), commission (`commission_settle`), settlement cash movement (`cash_delta_settle`), and the pre-trade position state. Trades accumulate in `Account.trades`.

## Position

A `Position` maintains the net exposure for an instrument using a weighted-average cost basis. It stores the average prices, quantity, and unrealized P&L caches (`pnl_quote`, `pnl_settle`). For asset-settled instruments, `pnl_settle` includes both quote-price move and FX translation versus `avg_entry_price_settle`. Positions are stored in `Account.positions`.

## Instrument

`Instrument` models a tradable product, binding together the display symbol, base asset settings, and quote asset settings. Instruments must be registered with an account before use using the `register_instrument!` function. Contract type (`contract_kind`) and lifecycle bounds (`start_time`, `expiry`) let you represent spot pairs, perpetual swaps, and dated futures explicitly.

### Spot on Margin

An asset-settled spot instrument with an explicit margin mode (percent-notional or fixed-per-contract) represents "spot on margin". Use `is_margined_spot` to detect this case; leveraged longs/shorts post margin, and shorts can accrue borrow fees via `short_borrow_rate` (borrow-fee clocks are tracked per position and aligned to fills).

## Base Asset

The base asset represents the tradable quantity of an instrument (e.g. shares, contracts, coins). Instruments define their base symbol, tick size, min/max quantity, and display precision via `base_symbol`, `base_tick`, `base_min`, `base_max`, and `base_digits`.

## Price

`Price` is a type alias for `Float64` used for quote-currency values—trade prices, commissions, P&L figures, and so on. Quote precision and tick sizes are instrument-defined.

## Quantity

`Quantity` is a type alias for `Float64` describing position or order size. Positive quantities represent long exposure; negative quantities represent short exposure across orders, trades, and positions.

## Exposure

Exposure is the signed quantity of an open position. Helper predicates such as `has_exposure`, `is_long`, `is_short`, and `trade_dir` determine exposure state for `Position`s and `Account`s.

## Fill

A fill is the execution of an order (whole or partial). `fill_order!` creates a `Trade` with the fill price, fill quantity, remaining quantity, and realized P&L.

## Commission

Commission is specified by the active broker profile and converted from quote to settlement currency on each fill, then stored on the trade as `commission_settle`. This amount is applied to balances, equities, and realized P&L in settlement units.

## Realized P&L

Realized P&L is produced when exposure decreases (`realized_qty`) and is recorded gross of commissions as `fill_pnl_settle`.

For asset settlement, `fill_pnl_settle` equals closed-position realized P&L.
For variation-margin settlement, it includes both open mark-to-fill settlement and reduce-basis settlement.

Commissions are separate via `commission_settle`. The actual fill cash movement is always `cash_delta_settle`; for variation margin, `cash_delta_settle = fill_pnl_settle - commission_settle`.

## Unrealized P&L

Unrealized P&L is cached on positions as `pnl_quote` and `pnl_settle`. `update_marks!` keeps these caches in sync and mirrors the resulting value change into equity. For asset-settled cross-currency positions, `pnl_settle` includes principal FX translation from the settlement-entry basis.

## Trade Direction

`TradeDir` is the `@enumx` representing trade direction: `Buy`, `Sell`, or `Null`. Conversion helpers such as `trade_dir(quantity)`, `is_long`, `is_short`, and `opposite_dir` provide directional logic across orders, trades, and positions.

## Balance

A balance is the cash-only value associated with a `Cash` asset. Deposits, withdrawals, commissions, and realized P&L update balances; floating P&L from open positions does not. Access balances through `cash_balance(acc, cash)`.

## Equity

Equity is the balance of a cash asset plus the unrealized P&L of open positions denominated in that currency. Access equities through `equity(acc, cash)`.

## Cash Asset

A `Cash` object models a funding currency (USD, EUR, BTC, …) with display precision and a ledger-assigned index. `Cash` is owned by `CashLedger`. Register currencies through `register_cash_asset!(acc, CashSpec(:EUR))` to get account-owned `Cash` handles.

## Collector

Collectors are lightweight recorders that capture time-series or summary statistics during a backtest. `periodic_collector`, `predicate_collector`, `drawdown_collector`, and helpers like `min_value_collector` are part of the collectors API and return both the collecting closure and the mutable storage.

## Exchange Rate

`ExchangeRates` converts values between cash assets using a mutable matrix of pairwise rates and implied reciprocals.

## Batch Backtest

`batch_backtest` runs a vector of parameter sets across one backtest function, optionally multi-threaded, while reporting progress and optional callbacks.
