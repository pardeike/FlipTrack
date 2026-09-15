# Reference matcher generalization — 2026-09-11

Feasible as a common engine with per-family static masks, animation/layout variants
and temporal event interpretation. Exact full-image identity does not hold for
all semantic labels, and current ColorDMD reconstruction is incomplete.

## Independent attract reference

Supplied `Indiana Jones (Williams 1993).f4v` from
https://www.vpforums.org/index.php?app=downloads&showfile=7870 is a 2013 HyperPin
backglass preview (author bitupset), 1280×1024 H264 yuv420p, 30 fps, 60.699967 s,
3,937,917 bytes. SHA256:
`536624b3e7868ae338ae3da0d64d661273f0c05ba0d0a8e1bbc12b0ca2c8a9b0`.
It composites an orange rendered DMD into a static backglass. It is neither
ColorDMD colour evidence nor a real-camera lighting sequence.

After fitting on the IJ title at 0.000 s, one frozen registration gives:

| F4V image | Emulator source | Correlation | Pixels compared |
| --- | --- | --- | --- |
| IJ title, 0 s | attract-escape 85 | .922 | full image |
| Williams, 27 s | attract-escape 221 | .973 | full image |
| Highest scores, 5 s | attract-escape 145 | .966 | top 8 rows |
| Highest scores, 15 s | attract-escape 161 | .966 | top 8 rows |

The 5 s video uses different initials, rank and score from its emulator comparison;
all of those pixels were excluded. Initial comparison against an animated highest-
score frame gave .659; using the stable header variant gives .966. This is exactly
why animation phase needs explicit treatment. These scores are not probabilities.

A new 180 s emulator capture (714 changed frames, nominal 60 Hz) produces title,
Williams, highest scores/grand champion, credits, GAME OVER and additional idle
screens after clearing the reset notices. The initial no-input attempt stayed on
reset notices and is retained as failed acquisition evidence. Attract title has an
unambiguous recovered colour-map candidate. Williams has both full-frame and
partial-mask colour candidates; precedence is not yet established. Some animated
GAME OVER and pinball-logo overlays erase foreground in the provisional compositor,
so they are not approved final colour images.

## Original-camera transfer beyond starts

The accepted Steal the Stones geometry was frozen, with no per-result adjustment.
Static top-title matching of result/bonus-recap panels correctly ranks:

- Tank Chase at 40:18.063: .914; next candidate .329.
- Streets of Cairo at 43:35.568: .889; next .312.
- Steal the Stones at 50:49.580: .841; next .417.

Six available named-total references were compared. Score digits and the optional
TOTAL line were masked. These tests identify a title inside a result family, not
a complete family/event classifier. Recap and immediate-total panels need variant
metadata; the optional TOTAL line must not create a new mode occurrence.

The attract GAME OVER reference matches the camera's post-game GAME OVER at
43:54.068 poorly (.488 full structure). A local refit only gives .603 and moves
corners 14–61 pixels on a 512×128 grid. It was rejected, not used to change the
accepted geometry. Same words do not establish the same visual variant. Short
central text is also poorly conditioned for full-display calibration.

## Adaptive colour experiment

A reusable research AdaptivePalette updates known camera RGB prototypes only after
independent structure >=.82, runner-up margin >=.12, 3 repeated matches, geometry
residual <=.75 and clipping <=3%. A .15 EMA with max RGB-vector step .035 bounds each
update. Those are experimental gates; production thresholds remain unvalidated.
Dynamic masks exclude both positive and negative probes and colour-update samples.

Synthetic gradual channel gains [1,1,1]→[.72,.83,.92] plus ambient offset .018 were
applied over 60 repeated observations of the three real aligned mode stills.
Starting palette learned from Tank Chase. 60/60 structural winners stayed correct;
48 updates accepted, 12 initial-in-sequence updates gated. Last 20 observations:
fixed-palette filled-pixel agreement .329, adaptive .744, measured before each
current-frame update. This demonstrates the mechanism under controlled synthetic
drift, not measured lighting robustness. Two tests pass for gate rejection,
bounded updates and exclusion of dynamic pixels.

## Intended native architecture

1. Detect the approximate DMD inside the guaranteed centred 4:3 acquisition region.
2. Acquire a full-plane homography from a stable, spatially distributed attract
   image: prefer IJ title; Williams can corroborate geometry. High-score header is
   useful recognition evidence but too narrow vertically to be the sole calibrator.
3. Verify over several frames/templates; track geometry and reacquire after motion.
4. Sample reference pixel centres directly from the camera via the homography.
5. Reject candidates using stable geometry and discriminating static probes, then
   use colour classes, full masked checks and short animation-sequence agreement.
6. Emit events through turn/game state, not once per matching image.
7. Confident observations offer colour samples; update only supported colours,
   cautiously, with a fixed reference and rollback checks to avoid feedback drift.

A colour-only or monochrome frame cannot identify the whole colour transform.
Glare/occlusion cannot be corrected by learning a global colour matrix. Geometry
must not be re-estimated from every sparse event panel. Native iPhone performance,
real-camera attract acquisition and adaptation have not yet been measured. Existing
review app currently renders calibrated stills through Python; this turn adds
research evidence/prototypes, not a live automatic calibration feature.
