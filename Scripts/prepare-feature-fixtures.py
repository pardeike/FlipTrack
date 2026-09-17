#!/usr/bin/env python3
"""Read-only extraction of selected private feature evidence; never accesses a device."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
movie = root / "Research/Local/source-original.mov"
expected = "a0374737c6a44fb5c18ee03456e2eca5c4e57595e3f1cf5ab5a603574f006d12"
with movie.open("rb") as stream:
    if hashlib.file_digest(stream, "sha256").hexdigest() != expected:
        raise SystemExit("Original movie fingerprint mismatch")
folder = root / ".build/feature-investigation/original"
folder.mkdir(parents=True, exist_ok=True)

def frame(name, time):
    path = folder / name
    if not path.exists():
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                        "-ss", str(time), "-i", str(movie), "-frames:v", "1",
                        "-q:v", "2", "-update", "1", str(path)], check=True)
    return str(path)

baseline = root / "Recognition/Tests/PinballTrackingTests/Fixtures/baseline-observations.jsonl"
starts = [item for line in baseline.read_text().splitlines()
          if (item := json.loads(line))["kind"] == "modeStart"]
samples = []
for episode, item in enumerate(starts):
    for offset in [0, 0.5, 1, 1.5, 2]:
        time = item["sourceTime"] + offset
        samples.append(dict(path=frame(f"mode-{episode}-{offset}.jpg", time),
                            time=time, mode=item["mode"], episode=episode))
for result, time in enumerate([2418.063, 2615.568, 3049.580]):
    for offset in [0, 0.5, 1]:
        samples.append(dict(path=frame(f"result-{result}-{offset}.jpg", time+offset),
                            time=time+offset, result=True, episode=12+result))
(folder / "manifest.json").write_text(json.dumps(samples, indent=2) + "\n")
print(f"Prepared {len(samples)} feature frames")
