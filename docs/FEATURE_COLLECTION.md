# Feature collection

Feature recognition is a separate observer of the production score pipeline.
It does not change turn tracking, game completion, scores, wins, or correction
controls. No feature UI is included. AP11 was in active use during development;
all validation for this addition is local and no deployment was performed.

## Collected meanings

| Screen evidence | Recorded meaning |
| --- | --- |
| Known mode title with instructions | `modeStarted`, named mode |
| Known mode title with a total | `modeScore`, `namedTotal`; never another start |
| Mine-cart tunnels-passed result | `modeScore`, `tunnelsPassed`, count and displayed score |
| Explicit MULTIBALL / numbered-ball MULTIBALL announcement | `multiballStarted`, optional ball count |
| Explicit MULTIBALL OVER / ENDED | `multiballEnded` |
| Jackpot title and amount, without qualification instructions | `jackpotAward` |
| Jackpot VALUE | `jackpotValue`; never an award |
| BALL SAVED / BALL SAVE / SHOOT AGAIN | Three distinct meanings; no inferred drain or save |
| BONUS / BONUS VALUE | Tally or status value, kept distinct |
| TOTAL BONUS / TOTAL MODE BONUS | End bonus or mode bonus total |
| Number of BALLS LOCKED | Lock status; never inferred multiball |
| EXTRA BALL AWARDED / EXTRA BALL LIT | Award announcement or lit status, kept distinct; bare EXTRA BALL is ambiguous |

The title catalogue covers Get the Idol, Streets of Cairo, Well of Souls,
Raven Bar, Monkey Brains, Steal the Stones, Escape in the Mine Cart, Rope Bridge,
Castle Grunewald, Tank Chase, Three Challenges, and Choose Wisely. Names and the
qualification/award distinction were checked against the
[Williams operations manual](https://documents.cdn.ifixit.com/cICCJLUXr3jA4KOq.pdf).
The catalogue is not evidence that all twelve identities or all screen variants
have been validated in camera pixels.

A mode title alone is insufficient. Support must be spatially near the title.
Single-line events require a located display, and attract/game-over/live-score
layouts are rejected. Narrow OCR aliases repair the observed Grunenald title
and UIDEO MODE instruction; arbitrary fuzzy title matching is not used.

## Confirmation and ownership

- Two distinct frame readings spanning at least 0.35 seconds confirm identity.
  Numbers require three agreeing readings within four seconds. An event can be
  saved with an unknown number and updated later under the same ID and a higher
  revision. Missing numbers never become zero.
- Repeated frames are one presentation. Two seconds of other recognized screens
  rearm that presentation; dark or unreadable frames alone cannot rearm it.
  Persisted events seed duplicate suppression after pause/restart.
- Context includes session, observed game ID/number, machine slot/ball, and person
  index. Restored context needs fresh confirmed score-screen evidence before
  ownership is trusted. Gaps over two seconds, corrections, recovery, and game
  boundaries discard pending votes and fresh-turn proof.
- A confirmed TOTAL BONUS retains the outgoing owner for its continuing bonus
  presentation, then requires fresh turn proof for subsequent play. A feature
  never serves as turn evidence. If a turn or its boundary was missed, attribution
  can remain unknown; this is not proof of perfect ownership through every gap.
- Named totals link to a start only when one start exists for that mode in the
  same known game/turn/person context. Distinct result variants remain separate
  observations linked to the same start; their amounts must not be added blindly.
- Collection is suspended during explicit recovery. Manual score editing and
  undo do not delete or rewrite historical feature observations.

## Storage and evidence

`Session.collectedFeatureData` is an optional additive SwiftData field containing
JSON `[CollectedFeature]`. Collection saves validate the current session snapshot
and upsert by event UUID/revision. This data is independent of the game records;
score edits cannot silently reassign an old feature to another person.

Each record carries its parsed meaning, original OCR text/confidence, context,
source and confirmation times, wall dates, recording IDs, revision, optional
mode-start link, supporting frame IDs, missing-image IDs, and telemetry run.
Source uptime is scoped to `recordingID`; revisions can have a different
`confirmationRecordingID`. The latest revision is durable in the session, while
`feature.accepted` JSONL entries retain the history of accepted revisions.

Supporting JPEGs use `feature-<event ID>-r<revision>-<frame ID>.jpg` under the
telemetry run's `images/`. Raw `frame` entries also include per-frame
feature candidates. The session stores semantics, not JPEG bytes. Existing
telemetry reports write failures and queue drops; inspect its `images` and
`imageErrors` fields before claiming an image is available. `missingImages`
records unavailable input JPEGs, not subsequent disk-write failures. Evidence
files remain local; any existing session synchronization only carries the JSON.

## Reproducible local checks

```sh
python3 Scripts/prepare-feature-fixtures.py
FLIPTRACK_FEATURE_FIXTURES="$PWD/.build/feature-investigation/original/manifest.json" \
  Scripts/check.sh
```

The extractor verifies the original recording's SHA-256 and reads it in place.
The 69 selected frames cover 12 start episodes (seven mode identities) and three
named-result samples. These are targeted regressions, not a full-movie false
positive measurement. A result visible in only one selected frame establishes
layout classification, not three-frame numeric confirmation.

The existing `FLIPTRACK_SIX_BALL_FIXTURES` replay additionally runs the collector
and real persistence against all 767 camera frames. It checks three starts
(Monkey Brains, Steal the Stones, Mine Cart), all six end-bonus totals with their
turn ownership, and the 19-tunnel/29-million result linked to Mine Cart. Its
`features.json` output retains the latest collected records. Existing six-turn
and final-score assertions still apply. Replay JPEGs are read as inputs; missing
embedded evidence images in those test records are expected.

Multiball announcements, jackpot awards, ball saves and extra-ball variants have
synthetic layout/semantic tests only so far. Actual lock and jackpot-value screens
supply negative evidence: those screens must not emit multiball or jackpot awards.
Physical throughput, long-session storage/thermal impact, CloudKit migration,
and the remaining camera screen variants need separate validation when AP11 is
available. Local tests/builds do not establish those properties.

The expanded `Scripts/check.sh --recording` additionally restores older score
fixtures. On September 17 it exposed four assertions in three legacy score tests;
all four reproduce on the unchanged build-19 source (`fca2bad`). They are retained
in the recognition plan and are not waived or counted as passing feature checks.
