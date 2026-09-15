#!/usr/bin/env python3
"""Extract reproducible, private regression frames from the recovered movie."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
movie = root / 'Research/Local/source-original.mov'
if not movie.is_file():
    raise SystemExit(f'Missing recovered movie: {movie}')
folder = root / '.build/live-fixtures'
folder.mkdir(parents=True, exist_ok=True)

def frame(name, time):
    path = folder / name
    if not path.exists():
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', str(time),
                        '-i', str(movie), '-frames:v', '1', str(path)], check=True)
    return str(path)

samples = [
    (0, 1.0, 1, 1, 0, 0, False),
    (1, 56.001666, 2, 1, 5539000, 0, False),
    (5, 490.013, 2, 3, 33970770, 204675660, False),
    (12, 966.525, 1, 1, 0, 0, True),  # Active zero is blinked off.
    (28, 2339.095, 1, 3, 28841440, 212386990, False),
    (37, 3092.115, 2, 1, 162000, 0, False),
]
manifest = [dict(path=frame(f'turn-{index}-{time:.3f}.png', time), slot=slot, ball=ball,
                 left=left, right=right, allowUnknown=unknown)
            for index, time, slot, ball, left, right, unknown in samples]
(folder / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
sequence = [dict(path=frame(f'switch-{i}.png', 55.001666+i*0.5)) for i in range(8)]
(folder / 'switch.json').write_text(json.dumps(sequence, indent=2) + '\n')

finals = []
observations = root / 'Recognition/Tests/PinballTrackingTests/Fixtures/baseline-observations.jsonl'
for line in observations.read_text().splitlines():
    item = json.loads(line)
    if item['kind'] != 'gameResult':
        continue
    scores = item['scores']
    finals.append(dict(path=frame(f'final-{len(finals)+1}.png', item['sourceTime']+0.5),
                       scores=[scores['1'], scores['2']] if '2' in scores else None))
(folder / 'finals.json').write_text(json.dumps(finals, indent=2) + '\n')
