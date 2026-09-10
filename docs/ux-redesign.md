# FlipTrack product and recovery design

Status: implementation compiled and locally checked. Further device installation
and launch are held until the user says “deploy”.
Confirmed product decision: save detected score pairs automatically, with obvious
Edit and Undo actions on the last saved pair. Recovery drafts require review before
scanning can continue. No confirmation is required for ordinary successful capture.

## Purpose

Keep an accurate, editable record of two-player pinball sessions. Recognition
helps enter scores. It cannot authoritatively identify whose turn it is, when a
game ended, or whether an identical score display belongs to a new game.

One interface serves handheld and mounted use. No inferred active-player mode.

## Sources of truth

1. Session: persistent player identities/names, date, saved games.
2. Current game: persistent identity, number, machine left/right player mapping,
   any captured/entered candidate, and its explicit recording state.
3. Saved game: persistent identity, number, scores keyed by player, recorded
   starting order, and an identity used to prevent duplicate saves.
4. Scanner: transient camera/OCR lifecycle. It proposes observations for the
   current game; it never owns player assignment or saved history.
5. View: which screen or editor is open. Navigation does not create a game,
   change player order, discard a candidate, or erase capture protection.

Changing a player's display name does not swap identity or scores. Correcting
one historical game's order does not change other games. Saving a game advances
the current game's number/order exactly once. Retrying a failed save must not
advance twice. Undoing a mistaken save must restore the prior current game,
rather than merely deleting a row and leaving the wrong number/order behind.

## Primary interface

- Sessions: resume an existing session or create one; readable dates, names,
  game count, and wins. Edit session names/date; delete with confirmation.
- Session score table: stable player columns, compact wins, game history as
  primary content, collapsed secondary statistics.
- Current-game strip: game number and machine order, with an explicit edit action.
  Joining mid-game uses this same strip and does not require a fictitious start event.
- One scan control area: status, record/stop, pause/resume, camera/table toggle.
  Status distinguishes paused, stopped, looking, unreadable, candidate available,
  save failure, and saved. It does not claim someone should play.
- Camera alignment: full-screen preview and optional centered guide, same scan
  controls, explicit return to scores. No preview layer exists on the table.
- Game editor: both scores, swap scores, game number, recorded starter.
  The game-number menu provides deletion with confirmation.
  Input is a local draft until Save; Cancel leaves persistent values unchanged.
- Session/current-game editor: names, date, current-game number/order.
- Manual score entry is always reachable and uses the same current game/save path.
- Scanner settings: camera framing/exposure/quality first; tuning under Advanced.

## Lifecycle and recovery

| Situation | Behavior |
| --- | --- |
| Open before play | Resume/create session; verify current-game order; start scanning when ready. |
| Open mid-game | Resume/create current game; set actual machine order; scan without waiting for zero scores. |
| Open on final scores | Offer capture for the explicitly selected current game; do not wait for a missing start marker. |
| Pick up phone | One-tap Pause stops capture and OCR, preserving current game/candidate. Do not infer a game transition from camera movement. |
| Edit while scanning | Pause before presenting the editor. Preserve current game and protection; clearly offer Resume afterward. |
| Background/interruption | Stop capture, invalidate in-flight callbacks, discard incomplete temporal evidence, persist durable state. |
| Return | Show preserved state and a reason for pause; explicit Resume. No silent reset or auto-save on return. |
| Freeze/force quit/relaunch | Restore session, current-game identity/order, pending candidate and save protection. Camera starts paused. |
| Wrong reading | Edit/reject candidate, or correct/undo saved capture according to the selected save policy. |
| Same screen repeats | No repeated save for the same game identity. |
| Same scores in a later game | Explicit new-game identity permits it; do not permanently blacklist a score pair. |
| Missed game | Manual entry through the same save path, with editable order. |
| Camera/permission failure | Keep scores and edits accessible; explain failure and provide retry. |
| Persistence failure | Keep candidate and order intact; retry or edit. Never show Saved before persistence succeeds. |

Unconfirmed readings may be discarded after interruption; a confirmed proposal
and every user edit must survive restart once persisted. No reliance on a zero
screen, TOTAL BONUS, GAME OVER, or FREE PLAY alone as a game identity boundary.

## Battery and responsiveness

- Foreground keep-awake is app-owned; restore the prior idle-timer setting when
  inactive/backgrounded.
- Capture and OCR stop on pause/background; no hidden preview on score screen.
- Retain bounded OCR cadence and one-at-a-time processing; drop stale frames.
- Crop before filtering/OCR when centered scanning is enabled.
- Avoid repeated identical status publishes and redundant OCR where practical.
- Use an appropriate capture frame rate, not full video rate merely to discard
  most frames afterward. Confirm hardware supports the selected rate.
- Keep user-visible quality choices simple; measure recognition at both sizes.
- Do not claim battery-life improvement from compilation or still-photo tests.
  Measure on device; ensure any optimization preserves short-screen recognition.

## Acceptance evidence

- State-transition tests: early/late start, pause, edit, background/relaunch,
  wrong capture, duplicate/repeated scores, undo, failed/retried persistence.
- Migration proof from the current schema, preserving existing sessions/scores.
- Signed build; no source compiler warnings.
- Rendered review: empty/populated session list, current-game setup, score table,
  candidate/recovery state, full editor, settings, camera/return, large text.
- On-device checks: pause/background/return, camera toggle, keep-awake, permission
  errors, frame cadence, and battery/thermal behavior.
- Regression: individual games visible while scanning, stable named columns,
  all user-facing data editable, no turn prompts, no table preview.
- Keep redesign scope intact until these requirements are implemented and verified.

## Implementation and verification — 2026-09-10

Implemented:
- Named score columns, compact wins, collapsed statistics, grouped scan controls.
- Automatic capture with a persistent last-saved pair and direct Edit/Undo actions.
- Full game editor; names/date/current-order editor; editing pauses capture.
- Persistent current-game identity, pending capture, scanning intent, and starter.
- Idempotent recording, stale-capture rejection, undo that restores an editable draft.
- Explicit scanner lifecycle states and restart-as-paused behavior.
- Explicit resume can capture final scores without requiring a missed zero screen.
- Undone/discarded raw readings remain excluded across restart; an explicit action
  permits capturing the same scores again when appropriate.
- Coordinated editor presentation when leaving full-screen camera.
- Supported-device capture cadence reduced to 15 fps; OCR remains bounded to 2 fps.
- Whole-app foreground keep-awake retained; obsolete UI helpers removed.

Verified locally:
- Signed iPhone build succeeds without source compiler warnings.
- Core tests pass, including persistence across new contexts, undo, stale captures,
  retries, repeated scores, and explicit resume.
- A disposable fixture created with the previously deployed model definitions
  migrates and retains its game; subsequent writes also succeed.
- Supplied-photo recognition checks cover centered/full framing and camera sizes.

Outstanding device checks:
- Rendered UI, large text, editor presentation, and camera/table navigation.
- Actual camera pause/background/return and foreground keep-awake behavior.
- Live machine screen cycles, autofocus, battery use, and thermal behavior.
- CloudKit account synchronization.

Deployment boundary:
- One installation completed before the user's instruction to hold deployment
  arrived. The app was not launched afterward by the agent.
- Do not install again or launch until the user explicitly says “deploy”.
- Simulator runtime downloads were canceled because the user is on mobile data.
  No simulator runtime is available and no further download is required to build.
