## Codebase extension plan

The following code is from my Julia backtesting engine package called Fastback.jl (code pasted below). Plan how to extend/finish it to support basic margin trading and futures contracts (perps and expiring futures) next to simple spot/cash trading. Some building blocks and functionality for margin trading have already been implemented. Pay attention to clean APIs, simplicity, performance and type stability, and importantly correctness of all calculations incl. FX awareness where needed. The backtesting engine should allow the user to backtest basic margin/futures trading as seen Interactive Brokers, but keep the naming generic. The goal is backtesting research ideas and algorithmic trading strategies, not a perfect replication of Broker mechanics, only what is really PnL relevant for strategies. Breaking changes are fine, even encouraged if the design/API/performance/clarity/ease of use can be improved. Create a detailed implementation plan with self-contained steps for extending the code base, so each step can be implemented and then verified/tested independently before moving to the next step. I'll pass each step to an AI agent for implementation. Unit tests already exist for the Julia code, but I didn't paste them here to reduce context size.

## Task instruction

Implement the following task for my Julia backtesting engine Fastback.jl.
Pay attention to clean APIs, simplicity, performance/type stability, and importantly correctness of all calculations incl. FX awareness where needed. Write idiomatic, clean Julia code.

## Efficiency review task

The following code is from my Julia backtesting engine package called Fastback.jl (code pasted below). The backtesting engine should allow the user to backtest basic margin/futures trading as seen Interactive Brokers. The goal is backtesting research ideas and algorithmic trading strategies, not a perfect replication of Broker mechanics, only what is really PnL relevant for strategies. Review the code of this Julia package for algorithmic efficiency. It should not unnecessarily allocate, use inefficient algorithms or data structures, or have type instabilities. This package is used for conducting backtests of algorithmic trading strategies.

## Correctness review task

The following code is from my Julia backtesting engine package called Fastback.jl (code pasted below).
The backtesting engine should allow the user to backtest basic margin/futures trading as seen Interactive Brokers or on Binance (ignore inverse contracts, options, and other exotics).
The goal is backtesting research ideas and algorithmic trading strategies, not a perfect replication of broker mechanics, only what is really PnL relevant for strategies.
Do a review for correctness of all calculations, and a consistent, intuitive API.
Assume the user uses the library carefully and correctly, so focus on correctness of the core logic and calculations, not on user input validation or error handling.
Only report major correctness issues, not minor style issues.
Do not assume all unit tests are correct, but focus on the core logic and calculations in the code itself.

Codex: Review my Julia backtesting package code for correctness of all calculations, especially PnL calculations, margin calculations, FX conversions, and handling of futures contracts.
Assume the user uses the library carefully and correctly, so focus on correctness of the core logic and calculations, not on user input validation or error handling.
The goal is backtesting research ideas and algorithmic trading strategies, not a perfect replication of broker mechanics, only what is really PnL relevant for strategies.
Identify any bugs or inaccuracies in the logic or formulas used.
Only report major correctness issues, not minor style issues.
Do not assume all unit tests are correct, but focus on the core logic and calculations in the code itself.
