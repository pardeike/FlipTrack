# FlipTrack recognition engine: recovery and first integration

Date: 2026-09-15. Approved working plan. Read this before each engine checkpoint and after context compaction. Keep the requirements and evidence distinctions intact; update the tracking section with actual results.

## Recovered sources

The MacBook Air responds at both `andreasair.local` and `mba.home.arpa`.

Research root on the Air:
`/Users/ap/Archive/Backlog/2026-09-13/Desktop - air/IndianaJones-ScreenCatalogue`

Its `ReviewApp` is a separate local Git repository, HEAD `88b0d43` (native replay detector and comparison). No Git remote is configured. `Analysis/colordmd/probe_families.py` is untracked. Preserve both Git history and untracked work before moving or integrating it. The parent directory includes the original 4,055,356,684-byte movie, reference images, annotation baselines, and run evidence that are not represented by source alone.

FlipTrack on the Air is `/Users/ap/Lab/FlipTrack`, at `0d2ff02`. That pulled commit contains ColorDMD/emulator browser snapshots and images, not the research engine. The shipping app contains its earlier Vision OCR final-score reader, persistence, and manual recovery controls, but no native research tracker integration.

Recovery is tracked below. Do not treat an inspection cache as a backup of source history, reference images, or recordings.

## What the evidence establishes

- The original recording is 3,095.513 seconds long (51m35.5s), with six complete games and the start of game seven.
- Native run v3 decoded 92,863 frames and analyzed 6,191 at approximately 2 Hz.
- It emitted 38 machine-turn starts and 12 mode starts across seven distinct mode identities. Turn starts include seven initial/new-game turns, not 38 human switches.
- The comparison has 49 matches within three seconds and one timing disagreement of nine seconds. No missing or extra events were reported for those two categories; synthetic person attribution agreed throughout.
- Confirmation delay was 0.5–3 seconds, median one second. Runtime was 342.514 seconds, 9.04 times real time on the Mac.
- This is performance and agreement on the same recording used to tune the engine. It is not held-out accuracy or AP11 performance.
- Thirteen sampled frames lost geometry around a camera movement. Tracking entered uncertainty and later recovered using repeated unchanged score evidence plus expected turn context. Broader recovery remains unproven.
- The native image detector does not emit final-score/game-result events. The tracker can consume such events, and annotated-fixture tests cover six results, but those are not six independently recognized results.
- One final score in the reviewed recording (game 2, slot 2) is occluded and intentionally unknown.
- A fresh `swift test --sanitize=thread` run on the Air passed 21 tests (3 vision, 10 tracking, 8 review-core). Full video replay was inspected through its saved results, not rerun during this audit.

## Existing components

### PinballVision

Native Swift/Core Image/Vision pipeline accepting images and timestamps. Uses projective registration against two calibrated setup images, external cabinet patches to validate alignment, selective scoreboard OCR, active-score glyph geometry, temporal turn votes, and optional mode matching.

The current implementation is a replay tool: it requires twelve mode references, uses a normalized portrait coordinate system, writes frame logs and evidence images, and owns an in-memory tracker. It needs a live-camera adapter, bounded diagnostics, state restoration, and a startup calibration appropriate to the current phone placement.

### PinballTracking

Codable Swift state with stable person identities, machine slot/ball/game context, event deduplication, source-time attribution, uncertainty intervals, explicit identity recovery, and finished-game handling. It preserves the established rotation rule: the person playing machine P2 at one game's end plays machine P1 at the next game's start.

It currently assumes two slots and balls 1–3. Same slot/ball repetition does not change person. Missing or unexpected transitions require recovery instead of guessing. A partial result marks a game finished, with no later score-amendment path; the integration must address that before feeding incomplete results into durable app state.

### Alignment and color

Continuous geometry alignment is required because nudging moves the cabinet relative to the phone. Retain this capability. The two reference poses bootstrap the existing replay; automatic fresh-session acquisition is not complete.

Local dot-grid refinement uses static ornaments from mode references. Dropping mode statistics does not mean deleting reference imagery that supports alignment.

Native turn recognition still has fixed green-footer and yellow-glyph gates. A separate Python adaptive-palette prototype updates supported colors only after strong structural identity, stable geometry, repeated evidence, little clipping, and bounded changes. Synthetic drift tests improved agreement, but it is not integrated into the native detector and has no live lighting validation. Treat it as a useful porting starting point, not a finished feature. Never let a doubtful match train its own color or geometry into agreement.

### ColorDMD and modes

Research recovered 1,599 legacy color maps and exact firmware recognition tags for twelve emulated mode starts. Synthetic composites supplied useful structure/reference images. Camera matching is tolerant image recognition, not direct use of exact firmware hashes.

Complete mode-end recognition was not finished; mode endings were explicitly made optional. Neither further mode statistics nor finishing CHROMA color-stream decoding is required for the requested first release.

## Narrow release contract

Target: AP11, iPhone 11 Pro, connected to power. Measure sustained latency and thermal behavior on that device. A Mac replay speed factor cannot select the iPhone processing budget.

After initial player/setup confirmation, capture complete final scores once per actual game, maintain trustworthy player/ball context, tolerate normal nudging, and explicitly stop making assignments when evidence is insufficient.

**Accepted first-release bar, 2026-09-16:** useful automatic capture with quick human recovery. Andreas considers 37/38 detected turn starts a win if the players can notice a problem and easily put tracking back on course. Perfect unattended detection and exact reproduction of every baseline event are not release gates. Keep reporting misses honestly; do not relax score validity or silently invent ownership to improve counts.

When tracking loses confidence, make that visible in the existing camera/session flow. Reuse the existing game-score editor and session/player-order correction UI. Add the scanner recovery interception below rather than a new correction screen. Resume from fresh, confirmed screen evidence without restarting the session or losing accepted scores. Keep unresolved older observations separate unless their ownership can actually be established, and prevent delayed pre-correction frames from undoing the correction. Measure correction frequency and ease of recovery during live acceptance, alongside automatic accuracy.

Turn changes must be confirmed from the next player's scoreboard context. Bonus screens, ball launches, locks, and the end of multiball are not sufficient by themselves. Turn detection establishes the first visible evidence of the next turn; it does not promise the exact physical drain timestamp.

Only completed games affect wins. When a player reaches ten confirmed wins, latch the race winner. If another game is already physically underway when confirmation arrives, finish and record that game before closing; do not start another. An automatically prepared next-game UUID is not start evidence. The first-to-ten winner remains the winner even if the trailing game changes displayed totals.

## Recovery interception on the existing score screen

User refinement, 2026-09-16: the game list already has score correction and
scanning controls. Reuse them. Add one recovery action, potentially a `→|`
symbol, near the existing scanning controls. Working accessible name: **Resync**.
The proposed name “Forced end of game” is misleading for a missed mid-game
switch; activation requests a fresh scan, not an unconditional completion.

1. Capture the current game ID, person-to-machine-slot mapping, and last known
   turn. Clear incomplete recognition votes and reject older queued callbacks.
   Suspend ordinary detection-driven state changes while the same camera,
   alignment and recognition path keeps running. This is not the existing
   `Scanner.pause`, which stops camera recognition.
2. Show a compact blocking **Scanning…** indicator with **Cancel** on the same
   screen. Keep the existing score list underneath; add no second correction
   editor or recovery dashboard. Do not require opening the camera preview.
3. If the last known turn was machine player 2, ball 3, expect final results.
   Ignore bonus, end animations, high-score entry and unrelated attract text.
   Wait for repeated agreement on the actual two-player last-game-score layout,
   then save both final scores once to the frozen game ID and apply normal
   game/session completion rules. There is no short fixed animation timeout.
4. For a missed switch within the game, the players wait before launching the
   next ball. Confirm the live scoreboard's active machine slot and ball number
   and read the outgoing player's post-bonus cumulative score. Update the
   current game's in-progress score evidence and re-anchor tracking to the
   visible turn. This does not save a completed game, add a win or advance the
   game number. Any unreadable score stays unknown.
5. Dismiss the blocker and resume ordinary detection only after the score and
   tracker update succeeds. Cancel commits no recovery result, clears pending
   votes and returns to the prior monitoring mode without pretending uncertainty
   has been resolved. Camera/persistence failures must remain actionable.

The expected branch is guidance, not proof: player 2 / ball 3 can have an extra
ball, and the stored turn may itself be stale. A live BALL screen must never be
saved as final results just because that branch was expected. Use fresh screen
classification and valid turn context; if the evidence cannot establish the
mapping, remain in recovery or let the user cancel and use existing corrections.
Final-score completion still requires a complete confirmed pair. Equal scores
in different games are valid; suppress duplicate saves by game identity.

### Existing implementation and remaining work

- `SessionView`, `GameEditView`, `ManualGameView` and `SessionDetailsView` already
  provide the score list, scanning controls, score editing and player/game-order
  corrections. Preserve that interaction model.
- `EndGameLayout` already parses final-result pairs and deliberately rejects
  BALL screens; `EndGameDetector` supplies repeated-reading confirmation.
- `GameDisplayLayout` recognizes bonus and zero-score new-game screens. It is
  not a general live-scoreboard reader. The recovered native engine supplies
  active-slot/ball observations, but still needs to be connected to score
  parsing and the app's current-game state.
- `Scanner` needs recovery routing within its existing camera callback, plus a
  generation boundary to prevent stale callbacks or ordinary saves racing the
  recovery result. The live scoreboard must not be passed through the existing
  final-result save callback.

Focused checks must cover both branches, long end animations, continued camera
delivery, cancel/no-write behavior, stale callbacks, one completion per game,
extra-ball/stale-context rejection and recovery after the observed AP11 loss.
Then prove the interception on AP11 using the existing score screen.

## Proposed implementation checkpoints

1. **Recover a reproducible baseline.** Preserve the research Git history, untracked script, reference pack, movie fingerprint, and recorded outputs. Import only needed Swift modules/fixtures with provenance. Keep the research datasets and ROM/firmware material outside the production app bundle. Resolve the research package's iOS 26 floor against FlipTrack's current iOS 18.2 floor rather than silently raising it.
2. **Run alignment and turn detection live on AP11.** Feed timestamped, correctly oriented camera images through one serial processing path. Begin around the already evaluated 2 Hz and measure before increasing it. Keep a visible preview independently of analysis. Acquire/confirm setup from the actual placement, follow nudges, and invalidate stale geometry. Retain useful reference-based refinement even though mode events are disabled. Port bounded color adaptation where color gates are used, with frozen last-good state and rejection tests.
3. **Join final-score recognition to game context.** Use the existing app's strict score parsing and temporal agreement on a reliable rectified display. Add game-ending evidence that distinguishes a live scoreboard from final results even when BALL text is missed. Combine readings across frames, retain post-bonus scores, and associate delayed finals with their originating game. Never substitute zero for unreadable data or save a partial pair as a confirmed win. Fix recovery/amendment handling for incomplete results.
4. **Persist a small, coherent session state.** One authority for person-to-slot mapping and game boundaries. Stable game IDs, atomic accepted-score updates, restart-safe duplicate suppression, calibrated setup state, explicit observed-start state, pending final results, and finishing/completed session state. Deduplicate by game identity, not score values: separate games can have identical scores. Corrections recompute wins. Existing score correction plus the scan-recovery interception and visible uncertainty are part of the first usable version. No new correction screen or mode dashboard.
5. **Prove the narrow contract.** Replay the original movie with the integrated engine, report exact score pairs, 38 turn starts, duplicates, unknowns, timing, and motion recovery. Leave the truly occluded score unknown. Then test a separate recording and live AP11 play including nudges, glare, saves/extra balls, missing bonus, obscured scores, restart, same-person new-game boundaries, and the ten-win/in-progress-game closing rule. Run a sustained plugged-in session and measure processed-frame time, queue backlog, confirmation delay, and thermal behavior.

## Recommendation

Build an OCR-led score/turn recognizer on top of the recovered alignment and tracking work. Reuse calibration references and cautious color normalization as supporting infrastructure. Do not port the full mode-statistics pipeline or infer turns from alternating bonuses. The next useful deliverable is a live AP11 alignment/turn-detection slice with inspectable evidence, followed by contextual final-score capture and session completion.

## Required AP11 performance prototype

Before claiming live readiness, build a separate development-signed app on AP11. Bundle the full original video as a local resource and run the physical camera concurrently. Feed replayed source frames to the same native recognition entry point intended for live capture, at original real-time pace with the intended analysis sampling. The physical camera supplies realistic acquisition load; it must not also run duplicate recognition on its frames. Retain the source fingerprint and distinguish this extra video-decoding cost from ordinary camera-only use.

Measure recognition service time (median, p95, maximum), source-to-confirmation time, scheduling lag/backlog, analyzed/skipped frames, camera frame delivery, elapsed duration, thermal state, and interruption/failure status. Report camera-off versus camera-on runs where useful. An unrestricted-speed run is a separate ceiling benchmark, not a replacement for a full paced run. Start with a short device smoke test, then replay all 51m35.5s. Verify recognized output against the existing 38-turn/12-mode baseline; future score integration must add exact score-pair checks. Keep the optional mode recognizer initially for baseline reproduction and workload comparison, not as product scope.

The prototype has its own bundle ID and output directory, no production CloudKit access, and no changes to saved FlipTrack sessions. A benchmark install is not authorization to replace the production web package. Save a machine-readable result that survives app exit and can be retrieved from the device. Incomplete, backgrounded, interrupted, or thermally constrained runs must be identified, not silently presented as completed throughput proof.

## Tracking

- [x] Locate and inspect the separate Air research repository and saved replay metrics.
- [x] Fresh research tests: 21 Swift tests passed with Thread Sanitizer on the Air.
- [x] Record approved scope, AP11 target, continued-game rule, and mandatory camera-loaded video benchmark.
- [x] Preserve full research history/untracked script, reference pack, and original movie locally with hashes.
- [x] Import a reproducible native engine package and focused tests without changing production behavior.
- [x] Build/install separate AP11 benchmark and verify a short smoke check with camera active.
- [x] Complete the full paced video run with camera active and verify sustained device performance.
- [ ] Add the scan-recovery interception to existing score-screen controls; reuse existing corrections and validate recovery on the AP11 failure.
- [ ] Live AP11 setup acquisition, motion tracking, and bounded color handling.
- [ ] Final-score and turn integration with persistence/recovery and race-to-ten completion.
- [ ] Independent footage and sustained real-machine acceptance.

Current checkpoint: build the live capture slice with explicit human recovery and final-score integration, using the AP11 ownership-loss case as a regression. Improve automatic continuity where straightforward; do not delay the useful version chasing perfect baseline agreement. Retain the measured 2 Hz budget. No engine changes have been deployed to production FlipTrack.

### 2026-09-15: baseline recovered, device harness implemented

- Recovered complete `ReviewApp` Git history as an independently verified Git bundle, the untracked research script, all native reference inputs and saved v3 outputs under ignored `Research/Local/`.
- Original movie copied from the Air; local and remote SHA-256 agree: `a0374737c6a44fb5c18ee03456e2eca5c4e57595e3f1cf5ab5a603574f006d12`. Input sizes/reference hashes are in `Research/provenance.json`.
- Imported native source and fixtures unchanged into `Recognition/`, with a focused package excluding desktop review UI. Local `Scripts/test-recognition.sh` passed 13 tests with Thread Sanitizer, strict-memory-safety checks and warnings as errors. This is test evidence, not a new video-accuracy run.
- Separate `Benchmark/` app builds for iPhone in Release. It includes the entire recording, concurrent camera capture, real-time paced recognition, per-frame timing/thermal/camera evidence and durable completion/failure reports. Canonical commands and limitations are in `Benchmark/README.md`.
- Physical AP11, iOS 27.0: first 60-second camera-loaded run completed. 1,800 decoded frames, 120 analyzed frames, 903 camera frames; camera's largest delivery gap was 81 ms. Processing median/p95/max: 217/296/912 ms. Scheduling lag p95/max: 5.6/617.5 ms; the startup backlog cleared by source time 1.5 seconds and final lag was 5.1 ms. Thermal state stayed nominal. Both turn events, ownership and timestamps matched the saved baseline exactly. The tracked report is `docs/research/ap11-smoke-20260915.json`; full traces remain under `.build/benchmark-results/run-9FFEEC61-537D-4393-ADE8-70D460B75EFF/`.
- After the smoke run, drained final camera callbacks before reporting counters and removed a concurrency capture warning. Rebuilt, signature-verified and installed that version. The full paced recording launched at **2026-09-15 20:47 UTC / 22:47 Stockholm**, expected to finish around 23:39 Stockholm if uninterrupted. Retrieve with `Scripts/benchmark-ios.sh verify AP11`. Do not mark full-duration performance passed based on the one-minute result.
- Active full-run directory: `run-8AA706CC-4242-47DC-9D35-69B9ABAF8853`. At source time 42.5 seconds, device evidence showed 646 camera frames, 214 ms processing, 5.1 ms scheduling lag and thermal raw value 0 (nominal). This confirms the run started with camera delivery; completion is pending. The verifier recognizes both named and raw-value thermal output and rejects unknown values.
- Production target and sessions remain untouched. Next decision: use the full run's event agreement, sustained processing budget, thermal trace and backlog to choose the initial live processing budget. Full replay still cannot prove fresh-placement acquisition, final-score recognition or an evening of live play.

## Evidence references

### 2026-09-16: full AP11 run retrieved and reviewed

- Completed all 3,095.5 seconds with camera active: 92,863 decoded / 6,191 analyzed frames and 46,438 camera frames. Recognition median/p95/max was 161/244/478 ms, all below the 500 ms interval. Maximum scheduling lag 20.5 ms, final lag 5.1 ms; thermal state stayed nominal. Device performance passed.
- The strict recognition verifier failed: 37/38 turn starts and 12/12 mode starts, with nine turn events and three mode events marked unknown after the movement at 38:46. Geometry recovered, but a misread final digit in the last pre-movement scoreboard removed the unchanged score needed to recover player identity. Full report and evidence fingerprints: `docs/research/ap11-full-20260916.md` and `.json`.
- The missing turn is near 51:31 at the start of game 7. Two inspected movie frames show an unobstructed BALL 1 display; this is separate from the known hidden final score. AP11 lacked the three resolved slot observations required before the clip ended. Investigate without treating a short, truncated observation window as a reason to reject the approach.
- Andreas recalls a friend blocking a final score with a phone while photographing it. Keep an obscured score unknown; an unobservable score is not a recognition failure. Accuracy reporting must distinguish occlusion, insufficient evidence and demonstrably incorrect readings.
- Andreas accepts 37/38 turn detection as a useful first version when the UX makes errors noticeable and easy to correct. Prioritize visible uncertainty, explicit player/ball recovery, and score integration. Automatic recovery improvements and active-zero detection remain useful follow-ups, not a demand for perfect detection before live use. Performance optimization is not the priority. Production final-score recognition and live-machine acceptance remain pending.

### Original research

- `ReviewApp/validation/native-video-replay-20260911.md`
- `ReviewApp/validation/native-tracking-and-motion-20260911.md`
- `ReviewApp/validation/reference-generalization-20260911.md`
- `ReviewApp/validation/colordmd-internals-20260911.md`
- `baseline/audits/player-turns-20260911/REPORT.md`
- `ReviewApp/Sources/PinballVision/NativeDetector.swift`
- `ReviewApp/Sources/PinballVision/FrameImages.swift`
- `ReviewApp/Sources/PinballTracking/SessionTracker.swift`
- `ReviewApp/Analysis/generalization/adaptive_colour.py`

### 2026-09-16: first production integration, local checkpoint

- Added a narrow live BALL/active-score reader, repeated turn confirmation, durable in-progress evidence, and current-player display. Production keeps iOS 18.2 compatibility. It reacquires rectangles or the FREE PLAY lettering on each analyzed frame, including after movement; it does not import the recording's two fixed calibration poses. Relative color gates support the active-digit geometry, with OCR-size corroboration. The adaptive-palette research and reference registration remain follow-ups, not claimed as integrated.
- Added Resync alongside scanning controls. Recognition and the camera continue while Scanning/Cancel blocks other edits. Recovery requires fresh, repeated outgoing-score evidence for a live turn or the actual complete final pair. Live screens cannot complete a game. Queued pre-intervention callbacks are fenced by capture time, and Cancel discards recovery candidates.
- Persisted game progress and the first-to-ten winner. Only recorded final pairs affect wins. An observed subsequent game can finish; allocating its UUID cannot extend the session. Existing score edits/swaps/deletes recompute the race. The existing manual editor remains the path for an unreadable final pair.
- Local Swift checks cover turn continuity, unexpected transitions, missing frames, stale recovery frames, cancel, extra balls, pending next-game evidence, storage, and first-to-ten completion. Six recorded images at 1080p/720p and an eight-frame player-switch sequence additionally check the production reader. The active-zero blink frame stays unknown. The sequence confirms P2 ball 1 and outgoing score 5,539,000 in both ordinary tracking and Resync. This is sampled recorded-video evidence, not a full-video accuracy result.
- `Scripts/check.sh` is the local Swift-test + signed iOS-build gate. Optional recording fixtures are supplied by `FLIPTRACK_LIVE_FIXTURES` and `FLIPTRACK_TURN_SEQUENCE`. AP11 recovery checks and deployment are pending at this checkpoint.
