# AP11 recognition benchmark

Separate development app: **FlipTrack Bench**, bundle
`net.pardeike.FlipTrackBenchmark`. No CloudKit entitlements or production session
storage. The production FlipTrack target is unchanged.

## Commands

From the repository root:

```sh
Scripts/test-recognition.sh
Scripts/benchmark-ios.sh install AP11
Scripts/benchmark-ios.sh smoke AP11
Scripts/benchmark-ios.sh verify AP11
```

`install` verifies all input hashes, generates the project, builds Release, verifies its signature and
installs. `smoke` launches a 60-second run; command success only proves launch.
Allow camera access on the phone when prompted. Keep it foregrounded and on
power. Use `full` instead of `smoke` for the entire 51m35.5s recording. `build`
does local build/signature verification without installation. Logs live under
`.build/logs/benchmark-*.log`.

`verify` retrieves results and checks completion, active camera delivery, the
recording fingerprint, p95 below 500 ms, no uncleared final backlog or serious
thermal state, and event identities/timestamps against the corresponding saved
baseline segment. It writes `verification.json` in the retrieved run directory.
Use `results` to retrieve an unfinished or failed run without asserting success.

The recovered recording and references must exist in `Research/Local/`; their
hashes are in `Research/provenance.json`. The app contains the full 4.06 GB
recording even for short tests. It is deliberately not published on the app
download page. The generated Xcode project comes from `project.yml`.

## What runs

The back camera captures 720p frames (15 fps when supported) and discards them.
Concurrently, AVFoundation decodes the bundled recording. A serial worker
normalizes selected frames exactly as the research replay does, then calls
`NativeDetector.process` at the original timestamps, sampling approximately
twice per second and waiting until their real-time deadline. If recognition
cannot keep up, measured scheduling lag grows; no unbounded queue of images is
created. Camera-off runs are available in the app for comparison.

The baseline detector still includes mode matching and research diagnostic
writes. That reproduces the recovered workload; it does not add mode statistics
to the product. Camera capture plus prerecorded-video decoding is additional
load compared with a camera-only production pipeline. Preview rendering and
production UI/persistence are not part of this first benchmark.

## Evidence

`results` copies Documents to `.build/benchmark-results/`. Each run has:

- `benchmark.json`: completion/error status, source fingerprint, frame counts,
  processing percentiles, scheduling lag, camera gaps and thermal states.
- `timing.jsonl`: per-analysis timing, cumulative camera frames and thermal state,
  so stalls and increasing backlog can be inspected.
- `run.json`, `frames.jsonl`, event images: recognizer output, including each
  event's source and confirmation timestamp.
- `provenance.json`: exact input identities.

`latest-benchmark.json` points to the latest run directory and its summary. An
initial incomplete report replaces the previous result before work begins, so
a killed app cannot leave a previous success looking like the current result.
Backgrounding cancels; camera interruption/stall fails the run. Thermal changes
are retained even if replay finishes. Read them before claiming sustained
performance. A full run must also be compared with the saved reference events;
a short run proves only the harness and sampled segment.

Follow the [approved plan](../docs/RECOGNITION_PLAN.md) for integration and
acceptance. This detector does not yet recognize final score pairs.
