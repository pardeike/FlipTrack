# Collection performance — September 17, 2026

The local release benchmark compares source `4ab1175` with the optimizations in
this change. AP11 was not accessed. The released build 19 remains unchanged.

| Work | Before | After | Measurement |
| --- | ---: | ---: | --- |
| Feature classification | 570.97 ms | 41.16 ms | Median whole pass over 836 recorded OCR frames; five warmed passes |
| Persist one event revision | 21.85 ms | 11.05 ms | Median of 20 updates in a 1,000-record / approximately 660 KB session; in-memory SwiftData store |
| Complete image recognition | 178.33 ms/frame | 176.61 ms/frame | Two warmed passes of 93 fixed camera/movie images; no meaningful improvement |

Feature classification is approximately 14 times faster. Event persistence in
this stress case spends approximately 49% less time on the main actor. These
are component measurements, **not** a claim that the whole app is 14 times faster.
Vision OCR dominates the end-to-end time. JPEG evidence encoding averaged about
2.4 ms per sampled frame and was not changed. Smaller collections benefit less
from the persistence cache; these numbers do not predict AP11 timings.

## Changes

- Normalize the fixed mode-title catalogue once and look up each observed title
  once. The old loop repeatedly normalized all aliases for each candidate title.
  Keep ambiguous aliases ambiguous and preserve all recognition requirements.
- Cache the decoded feature collection per loaded session. Reuse it only while
  its source bytes exactly equal the current stored bytes. External replacements,
  corrections, rollback, clearing and corrupt JSON cannot return stale records.
  Publish the cache after a successful save; clear it after a failed save.
- The cache is transient and main-actor confined. It retains one decoded array
  plus its source Data; it changes no persistent schema, image retention, save
  cadence or durability rules. Encoding and saving still happen for each accepted
  revision, so improvements cannot be attributed to dropping or delaying writes.

We also measured reusing a Vision text request. It preserved outputs but showed
no meaningful end-to-end gain; that experiment was removed. OCR accuracy mode,
resolutions, geometric checks, 2 Hz sampling, confirmation thresholds, score
ownership and recovery behavior remain unchanged.

## Reproduce

First prepare the existing private feature fixtures and replay the six-ball
recording so their `readings.jsonl` / `replay.jsonl` files exist. Then:

```sh
python3 Scripts/prepare-performance-fixtures.py
FLIPTRACK_PERFORMANCE_ROOT="$PWD/.build/performance" \
FLIPTRACK_PERFORMANCE_NAME=before \
  swift test -c release --filter recognitionPerformanceProfile
```

Run the same corpus after a change and explicitly compare semantic outputs:

```sh
FLIPTRACK_PERFORMANCE_ROOT="$PWD/.build/performance" \
FLIPTRACK_PERFORMANCE_NAME=after \
FLIPTRACK_PERFORMANCE_REFERENCE="$PWD/.build/performance/before.json" \
  swift test -c release --filter recognitionPerformanceProfile
FLIPTRACK_COLLECTION_PROFILE="$PWD/.build/performance/storage.json" \
  swift test -c release --filter collectionPersistenceProfile
```

Run performance measurements separately from other replay/build work. They warm
up Vision/Core Image, measure two pixel passes, five text passes and twenty
persistence updates, and compare feature/live/final/ball outputs without timing
threshold assertions. The corpus uses fixed sample indices rather than selecting
frames based on optimized results. `inputs.json` contains pixel/text hashes;
private images and raw reports remain ignored. When comparing older source,
copy the benchmark harness into a disposable checkout rather than changing that
source's detection code.

The before/after classification outputs agree for all 836 text frames and all
93 pixel samples. Correctness is additionally guarded by the existing full
767-frame six-ball, 210-frame movie, 64 stationary-camera and 69 feature-image
regressions. Cache replacement, rollback, clearing and corrupt-data checks are
part of the normal tests; five feature/storage tests also passed under Thread
Sanitizer. These remain local evidence, not physical-device acceptance.

Numeric evidence: [collection-performance-20260917.json](../Research/collection-performance-20260917.json).
