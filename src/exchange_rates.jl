using Dates

"""
Abstract type for exchange rates.

Exchange rates are used to convert between different assets,
for example to convert account assets to the account's base currency.
"""
abstract type ExchangeRates{AData} end

"""
Dummy exchange rate implementation which always returns 1.0 as exchange rate.
"""
struct OneExchangeRates{AData} <: ExchangeRates{AData} end

"""
Get the exchange rate between two assets.
"""
@inline get_exchange_rate(er::OneExchangeRates, from::Asset, to::Asset) = 1.0
