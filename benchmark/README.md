Run the runtime benchmarks from the repository root:

```sh
julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'
JULIA_NUM_THREADS=1 julia --project=benchmark benchmark/benchmarks.jl
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
methods perform the same amount of market-data work. Repeated FX and option quotes
isolate routing and margin work without introducing a data-feed benchmark.

Use the allocation tests for deterministic regression checks:

```sh
julia --project -e 'using TestItemRunner; TestItemRunner.run_tests(pwd(); filter=ti -> endswith(ti.filename, "performance_alloc.jl"))'
```

Timing thresholds are intentionally kept out of unit tests. Inspect scaling as
well as absolute times: unchanged positions should not increase sparse event cost,
and a mark batch should recompute each affected option group once.

Measured during this change on Julia 1.12.7, one thread, Intel Alder Lake
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
