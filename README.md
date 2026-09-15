![FlipTrackLogo](https://github.com/user-attachments/assets/73a95e57-81ec-4d07-8ae0-bff8487fecb3)

FlipTrack tracks two-player pinball scores, wins, and statistics across sessions.
The continuous scanner targets the Indiana Jones two-player final-score display.

## Use

Create a session or select one from the history. The last session you opened is
marked with a play icon in its existing row. The score table keeps each player's
column fixed, shows wins prominently, and places detailed statistics directly
below the game list.

Tap the current-game strip or **Players & game order** to set the game number,
player names, date, and machine order. Set the actual left/right assignment even
when joining a game already in progress. This does not change historical scores.

Tap the red record-style button to scan. Confirmed score pairs save automatically.
There are no inferred active-player or “Up next” prompts. Each successful save
advances the current game and alternates its proposed starting order.

**Edit** changes both scores, the game number, or the recorded starter. Game
numbers must be unique. **Undo** reopens the last saved game as an unsaved draft,
restoring its number/order. Review and save the draft, or discard it before
scanning again. Undone/discarded readings are remembered so the same bad reading
does not immediately reappear. **Capture same scores again** explicitly resets
this protection when a later game legitimately has the same score pair.

Scores are always editable: opening an editor pauses capture. Manual entry
uses the same current-game save operation. Deleting a historical entry removes
its scores without changing the current order; Undo is the action for reopening
a mistaken latest save.

The bottom controls group scanning status, record/stop, pause/resume, and camera.
Use Pause before picking up the phone. Backgrounding pauses capture automatically.
Returning or reopening the session offers Resume; it never starts the camera
automatically. The current game, player order, and any unsaved captured pair
survive relaunch. The full-screen camera is available even when recording is stopped or paused.
Preview does not save scores. With recording stopped, **Test live recognition**
opens a text-only scrolling log using the actual camera settings. Each recognized
text appears on one large, truncated line, newest at the bottom. Repeated text
is suppressed until it has been absent for five seconds. The latest 300 lines
are retained during the test. **Camera preview** returns to framing. Testing runs OCR only while enabled;
starting recording or closing preview clears the test. The bottom table button
returns to the preview-free table and stops the camera unless scanning is active.

FlipTrack keeps the iPhone awake throughout the foreground app, even when
scanning is paused. Normal idle-timer behavior returns when the app is inactive.
The camera stops on backgrounding and when paused on the score table. OCR is bounded to two readings per second,
and supported cameras capture at 15 fps rather than full video rate.

For a tripod, enable **Centered scan area** in scanner settings and keep the
whole display inside the yellow guide. OCR uses the centered landscape 4:3
rectangle. Full-frame scanning remains available. Exposure and quality are
primary settings; recognition/filter tuning is under Advanced. Settings apply
on the next start or resume.

## Recognition

Recognition runs on the device using Apple Vision and Core Image:

1. Find wide rectangular display candidates and correct their perspective.
2. Read two scores above a centered **FREE PLAY** label. Check their relative
   geometry and parse complete numbers, including thousands separators.
3. If glare obscures the frame, try the full image, then use a partial label to
   locate a crop, straighten it using the text angle, and read it again. A partial label alone cannot confirm a game.
4. Require at least four agreeing readings over at least 1.5 seconds, with 80%
   agreement in a bounded five-second history. Camera processing is capped at
   two frames per second; missed readings count against confirmation.
5. Save once, then wait for eight seconds of readable non-result frames before
   accepting a different score pair. A confirmed zero–zero start screen also
   unlocks registration immediately. Unreadable frames and camera stalls do not
   unlock registration. The last captured pair persists across app restarts and
   score edits, so a cycling result display cannot immediately duplicate a game.

There are no fixed screen coordinates or a required mounting distance. The
complete display and legible digits are still necessary. Repeated score pairs
are suppressed until explicitly allowed through **Capture same scores again**. The result
layout is a recognition heuristic, not a reliable end-of-game signal. Automatically
saved pairs remain visible and editable so a mistaken reading can be corrected.

A recognized **TOTAL BONUS** layout is excluded from final-score capture; it
does not change players. Start-screen detection is checked against six zero–zero
photos: a large 00, a smaller 00 to its right, and BALL 1 / FREE PLAY below.
The geometry is relative to those labels, allowing a changed mounting position.
A BALL label also prevents live scores from being treated as a final result.

Recognition, confirmation, and persistence are separate so other signature
layouts can be added later. Other game-event detection is outside this version.

## Build and test

Open `FlipTrack.xcodeproj`. The project uses Swift 6, supports iOS 18.2 or later,
and has been built with Xcode 27. The existing CloudKit configuration remains in
place. On-device installation requires signing with the configured development
team and an appropriate provisioning profile.

Run the focused recognition and SwiftData tests on macOS:

```sh
swift test
```

For a completed development-signed release, use the project command:

```sh
Scripts/release-ios.sh AP11
```

It runs the tests, assigns the next build number from the live FlipTrack catalog, creates a
signed archive, installs it when the selected phone is reachable, publishes it to the web, and
verifies the public download. It writes full output to `.build/logs/release-ios.log` and prints
only `ok` when every required step succeeds.

Optional private-photo regression tests take a JSON manifest containing absolute
image paths and manually verified score pairs. A `null` pair marks a negative
example, such as the GAME OVER screen without scores:

```json
[
  {"path": "/absolute/path/result.heic", "scores": [24274100, 37531870]},
  {"path": "/absolute/path/game-over.heic", "scores": null}
]
```

```sh
FLIPTRACK_PHOTO_FIXTURES=/absolute/path/fixtures.json swift test --filter handheldPhotos
FLIPTRACK_REFERENCE_PHOTO=/absolute/path/reference.heic swift test --filter changedMountingAngles
FLIPTRACK_START_PHOTOS=/absolute/path/start-photos.json swift test --filter startScreenPhotos
```

The start-photo manifest is a JSON array of absolute image paths. Its checks
require a detected start and no final result at all five image variants.

The photo tests use the same recognition code as the camera. They test the
original image plus 1920- and 1280-pixel heights, including 9:16 portrait-video crops. Photos are read without editing
the originals and are not bundled in the app or committed to the repository.
Without the environment variables, private-photo tests are explicitly skipped.

The optional storage-upgrade test accepts `FLIPTRACK_OLD_STORE`, pointing to a
**disposable** store created using the original `98996a5` model definitions, with
one session and one game numbered 8 with scores `[100, 200]`. It migrates and
writes that fixture; never point it at a real store.

## Validation boundaries

The development checks cover score parsing, relative layout geometry, temporal
confirmation, duplicate suppression, player assignment, SwiftData persistence,
and migration from the original schema. The supplied photo set includes six
final-score screens, one GAME OVER screen, and six zero–zero start screens, with handheld angles and glare.

Still-photo and core tests do not establish live iPhone camera
performance, autofocus, thermal behaviour, or the timing of the real machine's
screen cycle. Validate a complete pair of games with the mounted phone before
relying on unattended recording. CloudKit account synchronization has not been
live-tested in this update.

Camera session work follows Apple's [AVCaptureSession threading guidance](https://developer.apple.com/documentation/avfoundation/avcapturesession).
