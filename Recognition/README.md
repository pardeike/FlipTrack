# FlipTrack recognition

Recovered native engine from the separate MacBook Air research repository,
commit `88b0d43`. The Swift source and fixtures are imported unchanged at this
checkpoint. Package wiring excludes the desktop review UI. This package currently
requires iOS/macOS 26; the production app's deployment target is unchanged.

Run `Scripts/test-recognition.sh` from the repository root. Full test output is in
`.build/logs/recognition-tests.log`. The 10 tracking tests use annotated inputs;
the three vision tests do not establish camera recognition accuracy.

The approved integration and benchmark contract is in
[`docs/RECOGNITION_PLAN.md`](../docs/RECOGNITION_PLAN.md).

The original video, camera reference images, saved baseline outputs, full research
Git bundle, and untracked research script are recovered under ignored
`Research/Local/`. `Research/provenance.json` records input hashes. Source reports
are retained in `docs/research/`; links in those historical reports are relative
to the original research directory and may not resolve in this repository.

The current detector still includes mode matching to reproduce its baseline. It
does not recognize final scores. Do not wire it to production persistence until
the plan's score confirmation and ownership requirements are implemented.
