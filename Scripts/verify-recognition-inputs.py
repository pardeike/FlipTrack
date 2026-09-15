#!/usr/bin/env python3
"""Verify recovered benchmark inputs before packaging their provenance."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / "Research/provenance.json").read_text())
video = root / manifest["video"]["path"]
inputs = {video: manifest["video"]["sha256"]}
inputs.update({root / "Research/Local/References" / name: digest
               for name, digest in manifest["references"].items()})
for path, expected in inputs.items():
    if not path.is_file():
        raise SystemExit(f"Missing benchmark input: {path}; see Benchmark/README.md")
    with path.open("rb") as source:
        actual = hashlib.file_digest(source, "sha256").hexdigest()
    if actual != expected:
        raise SystemExit(f"Benchmark input hash mismatch: {path}")
if video.stat().st_size != manifest["video"]["bytes"]:
    raise SystemExit("Benchmark movie size does not match provenance")
