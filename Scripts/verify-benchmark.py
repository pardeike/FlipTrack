#!/usr/bin/env python3
"""Check a retrieved run against timing, camera and recorded event evidence."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
results = root / ".build/benchmark-results"
summary = json.loads((results / "latest-benchmark.json").read_text())
run = results / summary["outputDirectory"]
failures = []


def require(condition, message):
    if not condition:
        failures.append(message)


require(summary["completed"] and not summary.get("error"), "Run is incomplete or failed")
require(summary["cameraLoad"] and summary["cameraFrames"] > 0, "No physical camera load proved")
manifest = json.loads((root / "Research/provenance.json").read_text())
require(summary["sourceSHA256"] == manifest["video"]["sha256"], "Wrong recording fingerprint")
require(summary["lastSourceTime"] >= summary["targetSeconds"] - 0.6, "Replay stopped early")
require(summary["processingP95MS"] < 500, "Processing p95 exceeds the 500 ms sampling interval")
require(summary["cameraMaxGapMS"] < 3000, "Camera delivery stalled")
thermal_names = ("nominal", "fair", "serious", "critical")
thermal_values = {name: name for name in thermal_names}
thermal_values.update({f"NSProcessInfoThermalState(rawValue: {index})": name
                       for index, name in enumerate(thermal_names)})
thermal = {thermal_values.get(value, "unknown") for value in summary["thermalStates"]}
require(bool(thermal) and "unknown" not in thermal, "Unrecognized or missing thermal evidence")
require(not ({"serious", "critical"} & thermal), "Thermal constraint needs review")
if failures:
    raise SystemExit("\n".join(failures))

timing = [json.loads(line) for line in (run / "timing.jsonl").read_text().splitlines()]
require(len(timing) == summary["analyzedFrames"], "Missing per-frame timing evidence")
require(bool(timing) and timing[-1]["lagMS"] < 500, "Replay did not clear its scheduling backlog")
actual = json.loads((run / "run.json").read_text())["events"]
baseline = json.loads((root / "Research/Local/Baseline/run.json").read_text())["events"]
expected = [event for event in baseline if event["confirmedAt"] <= summary["lastSourceTime"] + 0.0001]
require(len(actual) == len(expected), f"Event count differs: {len(actual)} vs {len(expected)}")
for index, (found, reference) in enumerate(zip(actual, expected)):
    require(found["kind"] == reference["kind"] and found["parameters"] == reference["parameters"],
            f"Event {index} identity or ownership differs")
    for field in ("sourceTime", "confirmedAt"):
        require(abs(found[field] - reference[field]) <= 0.51, f"Event {index} {field} differs by more than one sample")
report = {"passed": not failures, "failures": failures, "summary": summary,
          "eventsCompared": len(expected), "events": actual,
          "lastLagMS": timing[-1]["lagMS"] if timing else None}
(run / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
if failures:
    raise SystemExit("\n".join(failures))
