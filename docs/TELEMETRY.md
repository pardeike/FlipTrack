# Local telemetry and score evidence

FlipTrack writes to `Documents/Telemetry/<UTC launch time>-<UUID>/` for every app
launch. The folder contains `events.jsonl` and an `images/` directory. Nothing is
uploaded by this logger. Existing runs are retained until you remove them.

## Retrieve a run

Connect and trust the iPhone on the Mac. In Finder, select the iPhone, open
**Files**, expand **FlipTrack**, and drag **Telemetry** onto the Mac. The same
Documents folder is exposed in Files on the phone under **On My iPhone → FlipTrack**.
Copy the whole run folder so image references remain usable. Stop scanning before
copying a finished run; an active run can still be growing.
Deleting or replacing the active run makes logging fail visibly. Restart the
app to create a new run after doing so.

For development, `xcrun devicectl device copy from --device AP11 --domain-type
appDataContainer --domain-identifier net.pardeike.FlipTrack --source
Documents/Telemetry --destination PATH` retrieves the same files. Use an actual
local destination in place of PATH.

## Contents

Each JSON line has schema version 1, a sequence number, UTC wall time, monotonic
uptime, event name, payload, image paths and image-write errors. Sequence numbers
restart for each run. A forced termination can leave an incomplete last line;
readers should retain all preceding complete lines.
Writes and flushes run off the main thread. The pending payload/image queue is
limited to 16 MiB: if storage falls behind, the app reports the failure and the
next accepted event includes the number skipped in `droppedEventsBefore`.

- User actions include opening/closing editors, submitted manual scores, score
  swaps, save/delete/undo requests and outcomes, player/game-order corrections,
  scanning, pause/resume, Resync/Cancel, camera preview, and recognition testing.
  Submitted changes are logged with before/after session snapshots. Typing each
  individual character is not logged. Settings changes record the new settings.
- Every analyzed frame, at most twice a second, records its unique ID, capture
  uptime, processing duration including JPEG encoding when available, OCR text/confidence/geometry,
  parsed live/final scores and image availability. These are observations, not
  automatically accepted scores. Scanner status, stale-frame rejection,
  correction boundaries, confirmation, persistence and failures are separate
  events. Preview test readings are identified separately.
- App lifecycle and memory warnings are logged. Battery, charging state, low
  power, free disk space and iOS thermal state are sampled at startup and every
  30 seconds while the app is active. iOS thermal state is a category, not a
  temperature in degrees.
- `score.progressConfirmed` and `score.finalConfirmed` save the agreeing JPEG
  inputs before attempting the database update. Their corresponding `Accepted`
  events establish successful persistence. A confirmation alone does not prove
  a save. Missing images and write errors are explicit; a telemetry failure
  appears in the app and does not discard otherwise valid game scores.

Image names include game number, ball and active machine slot, or `final`, plus
unique confirmation/frame IDs. For example:

`game-007-ball-2-active-p2-<confirmation UUID>-<frame UUID>.jpg`

The ball/active slot identify the visible screen when recognition occurred. A
screen can supply both players' cumulative scores, including the outgoing
player's score. Use the event's before/after context for person attribution.
Images are the input passed to the reader, including the selected scan crop and
optional filter. Internal perspective-corrected OCR bounds can be relative to a
located display within that image. Only confirmed evidence is written to disk;
there is no continuous video recording. Manual scores have no invented image.

## Corrections remain authoritative

The scanner reads a fresh value snapshot of the session before every frame.
Changing game identity, scores/history, player assignment, game number, progress,
rejected readings, pending drafts or completion invalidates unconfirmed votes and
queued older frames. Resync also starts from that current state. After its own
successful save, the scanner adopts the newly saved snapshot.

Opening an editor pauses scanning. Save or cancel, then use **Resume** to continue
with fresh recognition. Corrections from another source while scanning also
invalidate pending recognition. An externally created pending draft pauses
scanning until it is reviewed or discarded. Manual score addition remains
available for a completed session; it does not automatically restart scanning.

After recording a game, a durable next-game latch prevents the same static final
screen from being saved again, including after manual addition or app restart.
Confirmed live play clears the latch. Use **Resync** to explicitly join a game
whose start was missed, or the existing identical-score action when appropriate.
Historical score edits never rewrite the raw captured-pair duplicate guard.
Undoing an older result preserves the identity, player order and progress of an
already-started next game, including across app restart. Saving the reopened
result restores that game. Inserting a missing historical result recomputes who
first reached ten wins in game-number order.

## Verification

Use `Scripts/check.sh --recording` for core, persistence, image-selection and
recorded-pixel checks. `Scripts/test-ios.sh DEVICE_ID` exercises the editing and
recovery controls in the isolated test app. `Scripts/check-camera.py --device
AP11 --reuse-benchmark` adds physical-camera checks for corrections during
recognition, player attribution after manual addition, undo/discard and retrieved
JSON/JPEG evidence. It restores the separate benchmark app afterward.

Telemetry and accepted evidence add storage and JPEG work. Short camera-loaded
checks measure this version, but sustained real-machine play is still the
acceptance boundary for an evening's operation.
