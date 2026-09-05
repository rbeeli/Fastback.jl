Run the runtime benchmarks from the repository root:

```sh
julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'
JULIA_NUM_THREADS=1 julia --project=benchmark benchmark/benchmarks.jl
JULIA_NUM_THREADS=1 julia --project=benchmark benchmark/scaling.jl
```

The separate environment uses the local Fastback checkout. BenchmarkTools stays
out of the library's runtime dependencies. Run baseline and candidate checkouts
on the same machine, without competing test/build jobs.

The suite reports warmed median time, bytes, and allocation counts per operation.
Setup and invariant checks are outside the timed regions. Each step advances time;
mark steps also alternate prices. Fill blocks construct fresh orders and alternate
buys and sells to bound exposure. The retained-history case keeps 100,000 distinct
orders and trades per sample to include sustained allocation and GC costs.

Cases cover sparse updates as the instrument registry grows, financing with one
eligible short, spot and variation-margin fills with both recording policies,
related/unrelated FX routes, option mark batches, and option fills in large groups.
An option-mark operation means the entire chain update, so individual and batched
methods perform the same amount of market-data work and alternate quote prices.
The original FX cases repeat quotes to isolate routing and revaluation.

`scaling.jl` adds changing FX with mostly flat registered positions, no-op
rebalances, actual open/close transitions, simultaneous expiries, and sparse
option marks in both long-only and mixed groups. Expiry setup copies an account
outside the timed region; expiry processing and index cleanup are timed.

Use the allocation tests for deterministic regression checks:

```sh
julia --project -e 'using TestItemRunner; TestItemRunner.run_tests(pwd(); filter=ti -> endswith(ti.filename, "performance_alloc.jl"))'
```

Timing thresholds are intentionally kept out of unit tests. Inspect scaling as
well as absolute times: unchanged positions should not increase sparse event cost,
and a mark batch should recompute each affected option group once.

Measured for 0.12.0 on Julia 1.12.7, one thread, Intel Alder Lake
(baseline commit `4af3840`; warmed synthetic fixtures):

| Operation | Before | After |
| --- | ---: | ---: |
| Default step, 10,000 instruments, one changing mark | 26.56 µs | 31.7 ns |
| Unrelated FX update, 1,000 open cross-currency positions | 8.02 µs | 29.1 ns |
| Relevant FX update affecting all 1,000 positions | 8.02 µs | 7.94 µs |
| Fresh spot fill without history | 31.6 ns, 64 B | 22.3 ns, 0 B |
| Fresh futures fill without history | 29.7 ns, 64 B | 21.9 ns, 0 B |
| Single option fill in a 512-position group, without history | 12.82 µs, 64 B | 9.36 µs, 0 B |

The default-step fixture has no financing charges or due expiries, but all default
phases remain enabled. Financing with one eligible short measured 56–63 ns per
step across registries of 1–10,000 instruments. Batched option marks remain the
preferred existing API for chain snapshots. Retained history still allocates the
required Order/Trade objects (208 B per fill in the fixture).

These figures isolate engine work; they are not whole-strategy speedup guarantees.

Further scaling improvements, relative to 0.12.0 (`9802fda`), on the same
Julia/CPU/thread configuration (rounded warmed medians):

| Operation | Before | After |
| --- | ---: | ---: |
| Changing FX, 10,000 registered instruments, one open | 62.4 µs | 44 ns |
| Single changed option quote, 512 long positions | 4.44 µs | 21 ns |
| Single unchanged option quote, 512 long positions | 4.45 µs | 18 ns |
| Single option fill, 512-position group, no history | 9.31 µs | 5.21 µs |
| Open/close first future among 10,000 open positions | 701 ns | 58 ns |
| Expire 10,000 futures together, no history | 4.78 ms | 0.79 ms |
| No-op rebalance, 10,000 registered instruments | 27.7 µs, 161,808 B | 81 ns, 96 B |

All rows except rebalancing allocate zero after warmup. Rebalancing retains
caller-owned result vectors and its empty default roll argument; its allocation
no longer grows with the inactive registry. Changed marks in mixed option groups
still require a group calculation. Ordinary spot/futures fills remain about
22–23 ns without history, and default sparse mark steps about 30 ns. Active-index
storage is reserved at registration; rebalance scratch storage is created lazily.
