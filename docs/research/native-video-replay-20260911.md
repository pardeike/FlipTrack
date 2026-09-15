# Native original-video replay — 2026-09-11

## Result and scope

`native-run-v3` read the 3,095.513-second original Photos movie in place. It decoded
92,863 frames, analyzed 6,191 frames at approximately 2 Hz, and finished in
342.514 seconds: **9.038x real time on this Mac**. No exported or reencoded video
was used. The native detector does not read baseline annotations or cached OCR.

| Measurement | Result |
| --- | ---: |
| Player-turn events | 38 |
| Mode-start occurrences | 12 (7 distinct identities) |
| Missing / extra versus proposed baseline, these categories | 0 / 0 |
| Pairs within 3 seconds | 49 |
| Larger timing disagreements | 1 |
| Unknown or wrong synthetic person attribution | 0 |
| Event confirmation delay in source time | 0.5–3.0 s; median 1.0 s |
| Analyzed frames without reliable geometry | 13 |

Machine slots, balls, and mode names pair one-to-one within a 30-second search
window. A pair is marked Timing if the difference exceeds 3 seconds. This
prevents duplicate output from being hidden by many-to-one matching. These
thresholds are explicit review conventions, not approved timing accuracy.

The recording was used to develop and tune the detector. This is **in-sample
agreement with a proposed baseline**, not held-out accuracy or proof that no
unannotated events exist. Twelve reference definitions are loaded; only seven
mode identities have camera evidence here. No final-score, win, jackpot, lock,
bonus, or mode-ending events are emitted by this initial native image detector.

## Timing item for review

Game 5, machine Player 2, ball 1:

- Native first evidence: **30:34.048**, confirmed **30:36.548**.
- Existing baseline: **30:43.048**.
- Native crop already shows large active `00` on the right, `BALL 1`, and the
  inactive left score `19,961,330`. The later baseline crop has `116,000` on the
  right. This supports an earlier turn start; baseline timing remains unchanged
  for review. The previous audit's complete count and order of turns still hold.

Use Detector > Timing in the review app. Both crops and separate timestamp jumps
are shown. All run separators remain visible under filters. Comparison loading
and navigation do not accept, reject or rewrite baseline proposals.

## Native implementation

`VideoDetect` uses AVAssetReader source PTS and passes oriented CIImages into
`PinballVision.NativeDetector`, then `PinballTracking.SessionTracker` interprets
confirmed observations. The processor accepts the app's initial player IDs; the
replay uses neutral `person-a`/`person-b`, since real initial identity is unknown.

The reference pack contains two manually calibrated camera setup images, their
quadrilaterals, an LED-plane correction, and twelve decoded ColorDMD mode images.
It contains no event timestamps or game-count hints. Setup images are training
inputs, not fully automatic setup. SHA-256 hashes are stored with the pack.

Each analyzed frame attempts native projective image registration against the
setup images. Cabinet patches outside the display validate the result. Tracking
can change translation, scale and perspective; seed selection uses image quality,
not the known camera-move timestamp. A short failed measurement may hold the last
pose, but prolonged failure stops screen recognition.

For modes, static blue frame/ornament samples fit a bounded local dot-grid
translation. Even columns fit and odd columns validate; these adjacent samples
are correlated and are not a truly independent camera dataset. Candidate fits
may be tested with held-out correlation >= .45 and improvement >= .005. Persisted
updates additionally require high identity similarity >= .78, margin >= .12,
held-out >= .65, bounded motion and the shared GeometryRefinement policy. This
is an initial experimental gate, not proof against all wrong references.

Mode identity uses normalized grayscale correlation over fixed title and
instructions. Similarity >= .68 and margin >= .08 pass directly. A weaker but
well-separated pixel candidate may request title OCR corroboration; only a single
glyph edit is allowed for long titles. Two temporal observations confirm a start.
Reappearing animation frames remain one episode until absent for over five
seconds. This has not yet been challenged with every long interrupted animation.

Turns combine selective scoreboard OCR with the position of large active score
glyphs, then temporal agreement. Bonus is not required. Fixed color heuristics
currently gate green footers and yellow score glyphs; adaptive color updates and
the full color-probe rejection cascade remain future work.

## Camera-move continuity

From 38:46.095 to 38:52.095, 13 analyzed frames lacked reliable geometry. After
five seconds of loss the interpreter explicitly entered uncertain identity state.
The last prior scoreboard included `28,841,440`; repeated post-recovery readings
preserved that nonzero score while the observed slot/ball was the expected next
turn. This corroborated an identity anchor at **38:57.095**, confirmed **38:58.595**.
All later turn and mode attributions match the baseline's synthetic mapping.

Recovery requires repeated unchanged nonzero score evidence plus same/next turn;
without that witness, attribution remains unknown. An identical OCR error or a
much longer gap could still mislead this heuristic. More occlusion, missing-game,
and camera-move footage is needed before treating this as production recovery.
The existing interpretation tests cover unresolved identity, explicit anchors,
turn order, persistence, duplicate observations and late attribution.

## Evidence and reproducibility

Dataset-relative paths:

- `baseline/research/native-references/references.json` and `sha256.json`.
- `baseline/research/native-run-v3/run.json`: event stream and throughput.
- `baseline/research/native-run-v3/frames.jsonl`: geometry, raw OCR, candidate
  similarities and local refinement measurements for all 6,191 analyzed frames.
- `baseline/research/native-run-v3/identity-recovery-1402256.json`: recovery reason.
- `baseline/research/native-run-v3/comparison.json`: full comparison rows.
- `baseline/research/native-latest.json`: review app's default run pointer.
- `validation/native-video-comparison-20260911.json`: version-controlled metrics.

Native event PNGs come from the 540x960 working image and a 640x160 display crop;
mode evidence includes the LED correction. They are diagnostic SDR working
stills, not native-resolution HDR exports. Existing baseline native stills remain
available for high-quality inspection. Source times allow re-extraction later.

`Analysis/prepare_native_references.py` prepares the independent pack.
`Analysis/evaluate_native_examples.py` uses annotation times to run selected
positive clips, explicitly for development; it does not measure false positives.
`Analysis/compare_native_run.py` reads annotations only after detection, applies
review corrections, and optionally updates the latest-run pointer.

## Validation and open work

The Swift package's 21 tests pass under Thread Sanitizer. The macOS Release review
app builds, and PinballTracking/PinballVision compile against the arm64 iOS 26 SDK
with complete concurrency and strict memory-safety checks. No iPhone application
was installed; camera throughput, battery, thermal behavior and live latency are
unmeasured. Mac replay throughput is not an iPhone performance prediction.

Native UI verification exercised original-movie playback, Page Down navigation
with automatic scrolling, search-field focus followed by Enter defocus and arrow
navigation, and persistent run separators while filtering to mode starts. The
app is left on the timing discrepancy with the final native-run-v3 loaded.

The next work is user review of the timing item, final-score extraction, a live
AVCapture adapter, and broader motion/color regressions. Automatic idle-based
setup, lock-wall reference refinements and ongoing color adaptation remain open.
The existing review crop calibration and the native detector's dynamic crop are
separate views; Detector's right-hand evidence is the native result at that event.

Implementation references: Apple's [AVAssetReader output provider](https://developer.apple.com/documentation/avfoundation/avassetreader/outputprovider(for:))
and [Vision homographic registration](https://developer.apple.com/documentation/vision/vnhomographicimageregistrationrequest).
