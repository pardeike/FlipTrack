# Adversarial review: corrections, score evidence and telemetry

Reviewed the build-15 implementation on 2026-09-16. The review used concrete
failure scenarios and regression tests. All five findings below have repairs;
the validation section distinguishes local fault injection from device evidence.

## Findings

### P1: inserting a missing historical win could retain the wrong race winner

`Session.record` counted accumulated wins using the cached winner, whereas score
edits recalculated the chronological race. A missing game inserted before the
tenth win could change who actually reached ten first without changing the
stored winner. Recording now uses the same chronological calculation as edits.
The regression inserts game 3 after game 20 and proves that the winner changes
to the person who reached ten in game 19.

### P1: undoing and resaving the winning result lost an already-started game

Undo replaced current progress with the reopened result's draft. Resaving that
result could close the session and discard the game already being played.
The session now persists that game's identity, number, starter and full progress
separately while a result is reopened, and restores it on save. Tests include
reloading the store and repeated undo/discard operations.

### P2: saved score images could include observations outside the voting window

Evidence retained five seconds of observations while live turn confirmation
used three seconds, and final confirmation also had a configurable history
limit. The evidence selector now applies those same time/count limits and clears
the buffer when recovery finishes. Regressions prove excluded old frames cannot
be presented as supporting evidence.

### P2: removing the active telemetry file could silently lose subsequent events

An open file handle can continue writing to an unlinked file after deletion in
Finder. Atomic replacement has the same problem despite a file existing at the
same path. Each write now checks the active file's identity and reports missing
or replaced storage through the existing visible telemetry error. Tests remove
the run folder and replace the JSONL file, then verify reported failures.

### P2: slow telemetry storage could block controls and accumulate memory

Synchronous flushes ran from the main actor, and queued image payloads had no
backlog limit. Flush now suspends asynchronously while the serial storage queue
works. Pending payloads/images are capped at 16 MiB. Overflow is visible and
the next accepted event records how many events were skipped. Deterministic
tests stall storage, prove the main actor remains responsive, and verify the
overflow/recovery gap count.

## Validation

- Nine new regression tests cover these cases. All 56 production-core tests
  pass. `Scripts/check.sh --recording` also passes the private recorded-pixel
  regressions and signed iOS build.
- Failure-before-fix logs remain locally under `.build/logs/adversarial-before.log`
  and `.build/logs/adversarial-storage-before.log`.
- AP11 passed all five physical-camera scenarios: turn recovery/cancel, recorded
  final images, recorded player switching, manual corrections during recognition,
  and undo/resave of the tenth win with a game already underway. The last case
  resumes tracking in game 11 with its original identity and no duplicate game.
  JSON/JPEG retrieval checks passed. The continuation screenshot was inspected.
- The recorded-input check processed 32 observations with the camera running:
  median 289 ms, p95 296 ms, maximum 469 ms; thermal state remained nominal.
  Machine-readable evidence: `research/ap11-adversarial-20260916.json`.
- All four iPhone 11 Pro simulator UI tests passed: recovery/cancel, manual
  addition/resume, recorded switching and final capture without duplication.
  Result bundle: `.build/device-tests-20260916-065958.xcresult`.
- Completed-release evidence is recorded below after delivery verification.

## Limits

Storage stalls and file removal were injected locally, not induced on the
user's production iPhone. Diagnostics remain best effort if storage is full or
the app is killed; a partial last JSON line must be ignored. No sustained
evening of live pinball, fresh lighting or repeated cabinet nudging was tested
by this review. Existing controlled replay results do not establish that.
