# Native tracking foundation and moving-cabinet evidence

Scope: first implementation slice of [the plan](../PLAN-iphone-stats.md).
The native image recognizer, frame adapters and detector-comparison UI remain
subsequent work. No video detection speed or iPhone battery claim is made.

## User evidence incorporated

The cabinet is dragged/rotated during right-side Narrow Escape nudging and
periodically moved back. A few centimetres of cabinet motion relative to the
tripod invalidate a fixed-pose assumption even if the camera itself stays put.
The user identified Ball 1/2/3 Locked crops as examples and explicitly confirmed
that the stone wall is static; the falling ball animates. Lock count is unrelated
to the current game ball number.

## Lock-wall experiment

`Analysis/calibration/lock_motion.py` uses all nine annotated lock evidence stills
after 39:00. It applies the existing late-position correction, then tests a
relative affine refinement against the first lock at 40:51.065. It fits only blue
wall regions at the left and right, excluding the entire centre, digits and ball.
Different spatial wall patches validate the fit; fitting and validation patches
are separated to reduce blur leakage. This is relative registration, not an
absolute ROM-to-camera calibration or a temporal tracker.

The old extraction pipeline already tracks cabinet features. These measurements
are residual errors after that tracking and the mode-derived correction. They
cannot establish physical cabinet displacement in centimetres.

| Evidence time | Held-out correlation before / candidate after | Largest candidate corner movement, DMD dots | Decision |
|---|---|---:|---|
| 40:51.065 | 1.0000 / 1.0000 | 0.000 | Anchor; unchanged |
| 41:26.565 | .9576 / .9426 | .843 | Reject |
| 42:14.567 | .9867 / .9751 | .582 | Reject |
| 42:55.567 | .9656 / .9802 | .521 | Accept |
| 43:20.068 | .9542 / .9794 | .992 | Accept |
| 44:31.070 | .9815 / .9783 | .415 | Reject |
| 47:00.573 | .9660 / .9702 | .618 | Accept |
| 47:38.075 | .9775 / .9761 | .389 | Reject |
| 49:46.078 | .9782 / .9773 | .482 | Reject |

Three of eight non-anchor stills improve; five retain their existing correction.
This supports evaluating refinements repeatedly, not accepting every computed
fit. Even fractions of a DMD dot matter when probing dot centres.

A separate synthetic affine movement applied to a real lock still was accepted;
held-out correlation improved .6596 to .9849, with maximum recovery error .2982
DMD dots at four interior test corners. A wrong-family mode-start image was
rejected (candidate held-out correlation .0620 and corner shift 40.86 dots).
These are bounded diagnostic checks, not broad accuracy or robustness results.

Artifacts under `../baseline/research/moving-cabinet/`:

- `lock-wall-comparison.png`: existing and accepted-refinement crops at equal size.
- `registration-mask.png`: green fitting patches, blue validation patches.
- `results.json`: matrices, metrics, decisions and original event/time provenance.
- Individual `*-fixed.png` and `*-refined.png`.

Original Photos video, native evidence and reviewed baselines remain unchanged.
The review application's renderer has not been switched to this experiment.

## Native module

`PinballTracking` is a Foundation-only Swift target for macOS/iOS. Its inputs
are confirmed semantic observations with source and delivery timestamps. It
does not classify pixels or accept a baseline document as detector input.

Implemented:

- Session-owned stable person IDs, game/slot/ball context and game rotation.
- Turn, mode-start and game-result output with deterministic occurrence IDs.
- Repeated scoreboards and repeated occurrence suppression; same-person saves
  or extra-ball displays do not create a switch.
- Source-time attribution of delayed observations; distinct delivery timestamps.
- Unknown scores remain unknown; no winner is inferred from a partial score pair.
- Continuity loss suspends identity inference until an explicit app identity
  anchor. Uncertainty intervals survive restart and remain in historical lookup.
- Codable state, including duplicate history; malformed input is rejected before
  mutation and delivery order is explicit.
- Small geometry-refinement acceptance policy with held-out improvement,
  distributed support, finite/nonsingular transform and corner-movement bounds.
  Rejected candidates retain prior calibration. Independent tracking loss freezes
  refinements until a separate acquisition succeeds.

The geometry gate receives quality metrics from a future fitting/tracking layer.
It does not estimate a homography, verify full conditioning/occlusion or validate
the supplied metrics itself. Thresholds are exploratory. Unknown score updates
and user corrections require recomputation/replay; a later recap is not counted
as another finished game.

## Reproduction and checks

```sh
python3 Analysis/make_tracking_fixture.py
swift test --sanitize=thread
swift run -c release TrackingReplay \
  Tests/PinballTrackingTests/Fixtures/baseline-observations.jsonl person-a person-b
../.venv/bin/python Analysis/calibration/lock_motion.py
```

The fixture is explicitly derived from baseline v3: 38 audited turns, 12 proposed
mode starts and six proposed game results. It contains no expected game number
or person assignment; expected values are in a separate test-only file. It does
contain annotated turn/mode/result observations and confirmed-new-game flags.
Therefore 56 correct outputs establish interpretation regression only, not
independent recognition, timing accuracy, missing-event recall or throughput.
Person IDs are synthetic because the recording's actual initial identity is unknown.

Snapshot/restart and duplicate ingestion are exercised after every fixture row.
Other tests cover missing transitions, late observations, no-bonus dependency,
unknown scores, repeated finals, tracking loss and native/Python gate agreement.

Validation commands additionally compile the native module for arm64 iOS 26
against the installed iPhoneOS SDK and build the existing macOS review project.
No device installation or live-camera validation is part of this slice.

Completed checks: 17 Swift tests passed with Thread Sanitizer (10 tracking tests
and seven existing review-core tests), arm64 iOS module compilation succeeded
with warnings treated as errors, macOS Xcode Release build succeeded without
warnings, and the Release CLI produced exactly 38 turn starts, 12 mode starts
and six game results with 56 unique event IDs. No review-required events occurred
in that annotated fixture. Native gate decisions match the recorded Python wall
experiment. The script's synthetic-recovery and wrong-family rejection checks
passed. `git diff --check` passed.
