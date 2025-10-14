# Glossary

## Account

[`Account`](@ref) is Fastback's central ledger. It keeps the registered cash assets, open positions, executed trades, account-level balances and equities, along with order and trade sequence counters. Construction and mutation helpers such as `register_cash_asset!`, `register_instrument!`, [`deposit!`](@ref), [`withdraw!`](@ref), and [`fill_order!`](@ref) are provided by the account API.

## Order

An [`Order`](@ref) encapsulates an instruction to trade an instrument at a specific time, price, and quantity, with optional `take_profit` and `stop_loss` levels and metadata. Orders translate into trades through [`fill_order!`](@ref).

## Trade

A `Trade` records the actual execution of an order, including fill price, filled and remaining quantity, realized P&L, realized quantity, commission, and the pre-trade position state. Trades accumulate in [`Account`](@ref).trades.

## Position

A [`Position`](@ref) maintains the net exposure for an instrument using a weighted-average cost basis. It stores the average price, quantity, and unrealized P&L (`pnl_local`), and powers helpers like [`calc_pnl_local`](@ref) and `calc_return_local`. Positions are stored in [`Account`](@ref).positions.

## Instrument

[`Instrument`](@ref) models a tradable product, binding together the display symbol, base asset settings, quote asset settings, and optional metadata. Instruments must be registered with an account before use using the `register_instrument!` function.

## Base Asset

The base asset represents the tradable quantity of an instrument (e.g. shares, contracts, coins). Instruments define their base symbol, tick size, min/max quantity, and display precision via `base_symbol`, `base_tick`, `base_min`, `base_max`, and `base_digits`.

## Price

`Price` is a type alias for `Float64` used for quote-currency values—trade prices, commissions, P&L figures, and so on. Quote precision and tick sizes are instrument-defined.

## Quantity

`Quantity` is a type alias for `Float64` describing position or order size. Positive quantities represent long exposure; negative quantities represent short exposure across orders, trades, and positions.

## Exposure

Exposure is the signed quantity of an open position. Helper predicates such as [`has_exposure`](@ref), `is_long`, `is_short`, and `trade_dir` determine exposure state for [`Position`](@ref)s and [`Account`](@ref)s.

## Fill

A fill is the execution of an order (whole or partial). [`fill_order!`](@ref) creates a `Trade` with the fill price, fill quantity, remaining quantity, and realized P&L.

## Commission

Commission captures execution costs in the quote currency. [`fill_order!`](@ref) supports both fixed commissions and percentage-based fees (`commission_pct`), applying them to balances, equities, and realized P&L.

## Realized P&L

Realized P&L is produced when exposure decreases. [`fill_order!`](@ref) computes realized P&L via `calc_realized_qty`, credits it to the account balance, subtracts commissions, and resets the position's P&L accordingly.

## Unrealized P&L

Unrealized P&L (stored as `pnl_local` on a [`Position`](@ref)) reflects the floating profit or loss based on the current mark price. `update_pnl!` keeps it in sync and mirrors the change into account equity without touching balances.

## Trade Direction

`TradeDir` is the `@enumx` representing trade direction: `Buy`, `Sell`, or `Null`. Conversion helpers such as `trade_dir(quantity)`, `is_long`, `is_short`, and `opposite_dir` provide directional logic across orders, trades, and positions.

## Balance

A balance is the cash-only value associated with a [`Cash`](@ref) asset. Deposits, withdrawals, commissions, and realized P&L update balances; floating P&L from open positions does not. Access balances through [`cash_balance`](@ref)(acc, cash).

## Equity

Equity is the balance of a cash asset plus the unrealized P&L of open positions denominated in that currency. Access equities through [`equity`](@ref)(acc, cash).

## Cash Asset

A [`Cash`](@ref) object models a funding currency (USD, EUR, BTC, …) with display precision and optional metadata. Cash assets must be registered with an account before funds can be deposited or withdrawn using the `register_cash_asset!` function.

## Collector

Collectors are lightweight recorders that capture time-series or summary statistics during a backtest. `periodic_collector`, `predicate_collector`, `drawdown_collector`, and helpers like `min_value_collector` are part of the collectors API and return both the collecting closure and the mutable storage.

## Exchange Rate

Exchange-rate providers convert values between cash assets. `OneExchangeRates` always returns 1.0, while `SpotExchangeRates` maintains a mutable matrix of pairwise rates and their inverses.

## Batch Backtest

`batch_backtest` runs a vector of parameter sets across one backtest function, optionally multi-threaded, while reporting progress and optional callbacks.
