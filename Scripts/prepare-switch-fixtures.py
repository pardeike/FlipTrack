#!/usr/bin/env python3
"""Extract the private September 17 switch regression; retain input identity."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('movie', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
expected = '6863670c1c5174eb59f228f43b91422362eb29dc59a4305387b561942b0a154f'
with args.movie.open('rb') as source:
    actual = hashlib.file_digest(source, 'sha256').hexdigest()
if actual != expected:
    raise SystemExit('Input fingerprint differs from the annotated IMG_0008.MOV recording')
folder = root / '.build/switch-fixtures'
folder.mkdir(parents=True, exist_ok=True)
subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(args.movie),
                '-vf', 'fps=2', '-frames:v', '210', str(folder / 'frame-%03d.png')], check=True)
samples = []
for index in range(210):
    time = index * 0.5
    slot, ball = ((2, 2) if time < 22 else (1, 3) if time < 57 else
                  (2, 3) if time < 80 else (1, 1) if time >= 96 else (None, None))
    samples.append(dict(path=str(folder / f'frame-{index + 1:03d}.png'), time=time, slot=slot, ball=ball))
(folder / 'manifest.json').write_text(json.dumps(samples, indent=2) + '\n')
(folder / 'provenance.json').write_text(json.dumps(dict(sha256=actual, bytes=args.movie.stat().st_size,
    source=str(args.movie.resolve()), samplingHz=2, samples=210), indent=2) + '\n')
