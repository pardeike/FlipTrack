#!/usr/bin/env python3
"""Prepare a fixed private performance corpus without accessing any device."""
import argparse
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--camera', type=Path, default=root / '.build/six-ball-results/camera')
parser.add_argument('--modes', type=Path, default=root / '.build/feature-investigation/original/manifest.json')
parser.add_argument('--output', type=Path, default=root / '.build/performance')
args = parser.parse_args()
# Fixed coverage of ordinary play, blinking digits, switches, feature/status
# screens and finals; no selection based on the optimized reader's output.
indices = sorted(set(range(0, 767, 16)) | {
    139, 140, 154, 161, 170, 238, 240, 339, 355, 360, 369, 408,
    417, 484, 496, 573, 585, 650, 706, 710, 711, 728, 731, 750})
pixels = [dict(path=str((args.camera / f'frame-{index:05d}.jpg').resolve())) for index in indices]
pixels += json.loads(args.modes.read_text())[::3]
text = ((args.camera.parent / 'replay.jsonl').read_bytes() +
        (args.modes.parent / 'readings.jsonl').read_bytes())
fingerprints = [dict(path=item['path'], sha256=hashlib.sha256(Path(item['path']).read_bytes()).hexdigest())
                for item in pixels]
args.output.mkdir(parents=True, exist_ok=True)
(args.output / 'pixels.json').write_text(json.dumps(pixels, indent=2) + '\n')
(args.output / 'text.jsonl').write_bytes(text)
(args.output / 'inputs.json').write_text(json.dumps(dict(
    textSHA256=hashlib.sha256(text).hexdigest(), pixels=fingerprints), indent=2) + '\n')
print(f'Prepared {len(pixels)} pixel samples and {len(text.splitlines())} text frames')
