![FlipTrackLogo](https://github.com/user-attachments/assets/73a95e57-81ec-4d07-8ae0-bff8487fecb3)

FlipTrack tracks two-player pinball scores, wins, and statistics across sessions.
The continuous scanner targets the Indiana Jones two-player final-score display.

## Use

Create or open a session, mount the iPhone in portrait with the entire display
visible, and tap **Start monitoring**. Tap the camera preview to enlarge it while aligning the mount. Leave FlipTrack open. It keeps the phone
awake while monitoring, records confirmed final scores, and continues watching
for the next game. Automatic mode gives the person who should act a large name
and prompt: **Come and play**, **Your turn**, or **Switch**. The other player is
a smaller reference showing their last score and session wins. After saving,
the next starter is called forward. Three readings of both scores at zero over
one second return the view to play; 0–0 is never saved as a result.

Stop monitoring to correct or delete an entry. Tap a score to edit it, or the game number for score swapping and deletion.

Use **Add scores** to enter a game manually in the display's left/right order.
The session list shows games played and wins for each player. New sessions open
immediately, and the game card shows who starts next.

Fredrik starts the first game, matching the existing app. The second player from
one game starts the next. Scores are stored under the players' names, regardless
of their left/right positions on the display. Deleting an old entry does not
change the next starter or reuse a game number.

Settings apply the next time monitoring starts. High Quality captures at 1080p;
the lower setting uses 720p. The exposure setting controls camera brightness.
The optional image filter remains available. Tap the small pause button in the
top corner before picking up the phone. The camera stops and the current game
state stays on screen. Put the phone back and tap play to resume. Going to the
background also pauses monitoring; returning does not resume it automatically.
Recovering from a camera interruption requires tapping **Start monitoring** again.

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
complete display and legible digits are still necessary. Two consecutive games
with exactly the same left/right scores are suppressed as duplicates. The end
layout is assumed to appear only after a game, as confirmed for this machine.

Current-player detection accepts a single explicit PLAYER 1 or PLAYER 2 prompt
inside a detected display, confirmed across two readings. It retains the last
known player through animations and unreadable frames. The supplied photos do
not show turn prompts, so active-player recognition still needs validation on
the machine. Start-screen detection is checked against six real zero–zero
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

Still photos and Simulator UI checks do not establish live iPhone camera
performance, autofocus, thermal behaviour, or the timing of the real machine's
screen cycle. Validate a complete pair of games with the mounted phone before
relying on unattended recording. CloudKit account synchronization has not been
live-tested in this update.

Camera session work follows Apple's [AVCaptureSession threading guidance](https://developer.apple.com/documentation/avfoundation/avcapturesession).
