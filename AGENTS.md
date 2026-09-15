# FlipTrack engineering contract

## Active recognition work

- `docs/RECOGNITION_PLAN.md` is the approved engine plan and evidence ledger. Read it before every implementation checkpoint and after context compaction. Keep the accepted requirements intact and update completed work, changed decisions, validation, and next steps there.
- Target AP11 (iPhone 11 Pro, iOS 27) on power. Continuous alignment must tolerate cabinet nudging. Preserve cautious color adaptation in scope; mode counting and other extended statistics are out of scope.
- Wins come only from complete confirmed final scores. Latch the first-to-ten winner, finish and record any already-started game, then close the session. A prepared next-game record is not observed start evidence.
- The separate AP11 benchmark must run the physical camera while replaying the complete original movie through the same recognition engine at real-time pace. Keep its bundle ID, data, and results separate from the production app. Mac replay speed, compilation, and installation are not physical-device throughput evidence.
- Preserve the recovered research history, untracked work, input fingerprints, and baseline metrics. Do not silently replace unknown scores with zero or infer a person switch from a bonus screen alone.
- First-release acceptance allows occasional missed turns when uncertainty is visible and a compact current-player/ball correction restores tracking without losing scores. Prioritize that recovery flow over perfect baseline agreement. Keep final-score confirmation and ownership safeguards intact; report automatic accuracy separately from assisted-session success.
- Reuse the existing game-score correction UI. Recovery is a scan interception on the score screen: show Scanning with Cancel, suspend ordinary state changes while camera recognition continues, then either confirm final scores or re-anchor a mid-game turn. Never turn a live scoreboard into a completed game. Follow the recovery section in the plan; do not add another correction editor.

## Workflow

- Use `Scripts/check.sh` for production-core tests and a signed iOS build. Optional recorded-pixel regressions use `FLIPTRACK_LIVE_FIXTURES` and `FLIPTRACK_TURN_SEQUENCE` manifests.

- Use `Scripts/test-recognition.sh` for the recovered engine's focused tests. Use `Scripts/benchmark-ios.sh build|install|smoke|full|results|verify [AP11]` for the separate device experiment. Launch success is not benchmark completion; inspect the retrieved results. See `Benchmark/README.md`.
- Use `Scripts/release-ios.sh AP11` for completed production versions. It tests, archives, signs, installs/launches, publishes, and verifies the signed web package. Development experiments must not replace the production web build.
- Keep full routine logs under ignored local paths and print `ok` only after every requested step succeeds. On failure, report the failed step, concise diagnostics, and log path; stop dependent steps.
- Stage intended paths explicitly. Preserve unrelated work. Keep video, build products, personal reference images, profiles, and research binary inputs untracked.
- Separate source/unit-test evidence, recorded-video recognition, device performance, and live-machine acceptance. Do not claim one proves another.
