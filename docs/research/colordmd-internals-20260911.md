# ColorDMD internals investigation — 11 September 2026

## Scope correction

The existing recording's player-turn sequence was already audited and fixed: **38 turn starts, six complete games and the first two turns of game seven, with no remaining missing, duplicate or ordering anomalies found**. The apparent missing P1/B1 events existed as new-game events and were reclassified consistently. See the [original audit](../../baseline/audits/player-turns-20260911/REPORT.md). The failed auxiliary emulator drain probe does not reopen that finding; it limits synthetic transition generation only. The audit did not establish frame-exact detection latency.

Andreas clarified that the required mode coverage is **which modes started, attributed to the correct player**. Complete per-mode ending statistics are optional. Missing success/failure result variants are no longer a blocker or mandatory filming target for that scope. The application supplies current human-player identity; the engine retains machine game/slot/ball context and must not blindly toggle a human identity at every new-game machine-slot reset.

## Concrete result

The firmware is substantially more accessible than the first type/header probe suggested. The investigation recovered a package directory, FPGA configuration signatures, sorted recognition tables, candidate rectangular masks, and **1,599 complete colour-index maps from official legacy IJ 3.4**. Most importantly, all twelve emulated mode starts generated exact recognition tags found in the legacy firmware and all three IJ CHROMA 4.1 images.

- [Keyboard-controlled firmware viewer](../../baseline/research/colordmd-firmware/decoded-legacy/index.html)
- [Twelve matched starts, composite and overlay](../../baseline/research/colordmd-firmware/decoded-legacy/matched-mode-starts.png)
- [Extraction/validation summary](colordmd-internals/summary.json)
- [Exact start-frame matches](colordmd-internals/mode-matches.json)
- [Compared binary inventories](colordmd-internals/inventory.json)
- [Decoder and reproduction commands](../Analysis/colordmd/README.md)

The viewer displays all 1,599 colour maps and the twelve matched mode-start reconstructions. Use arrows to browse, M to switch collections, Page Up/Down for ten, Home/End, and Enter to apply a typed index and release focus. Palette selection is manual. The composites are synthetic research images; their RGB values have not been calibrated against the installed ColorDMD.

## Source-led architecture, then binary verification

ColorDMD's [US8773452B2 patent](https://patents.google.com/patent/US8773452B2/en) describes masks, Jenkins hashes, sorted tag/pointer tables and run-length colour-index data combined with incoming game pixels. It also describes temporal processing. This supplied useful hypotheses, not a guaranteed specification for the downloaded releases. The following offsets, counts and successful decodes are direct measurements of the files.

## Compared files

All binaries came from links exposed by the manufacturer's [CHROMA catalogue](https://www.colordmd.com/support_firmware_chroma.html) or [legacy catalogue](https://www.colordmd.com/support_firmware_colordmd.html). Download URLs and hashes are retained in `comparison-downloads.json` beside the local binaries. They are not committed with the source code.

| File | Bytes | Observed image layout |
| --- | ---: | --- |
| IJ legacy 3.4 | 1,900,544 | Older single-file layout; 2,747 live tags, 1,599 distinct map pointers |
| IJ CHROMA 4.1 | 4,784,128 | 64 KiB directory + three 1.5 MiB images; each 2,747 tags / 1,259 distinct pointers |
| Attack from Mars CHROMA 4.1 | 3,997,696 | Directory + three 1.25 MiB images; each 4,104 tags / 1,866 pointers |
| SIGMA CHROMA 4.0 | 2,424,832 | Directory + three 0.75 MiB images; each one live tag/pointer |

This cross-file comparison makes the CHROMA directory interpretation much stronger than guessing from IJ alone. Entries at 0x10/0x20/0x30 each begin with length and start position, measured in 64 KiB units. Their sections account for every byte of all three CHROMA files.

Each CHROMA image has Xilinx sync bytes `AA 99 55 66` and a configuration IDCODE write of `04001093`. The packet pattern is consistent with [Xilinx's Spartan-6 configuration guide](https://docs.amd.com/v/u/en-US/ug380); the [xc3sprog device table](https://github.com/sifive/xc3sprog/blob/master/devlist.txt) identifies that ID as XC6SLX9. Thus the package includes FPGA configuration, rather than being solely a conventional CPU executable or image archive. The exact roles of its three variants remain unverified.

## Recognition recovered for all twelve starts

At legacy offset 0xA0000, 2,747 live eight-byte records contain numerically ordered big-endian tags and pointer/control words. Unused slots have the sentinel `FFFFFFFF 00000000`. After accounting for the low control byte, the pointer leads to colour data at `0xA0000 + (pointer >> 8)`.

Configuration contains 26 sixteen-byte mask records. Their first eight bytes can be interpreted as two inclusive rectangles. For mode starts, mask 14 selects the top seven rows across the full 128-dot width. The demonstrated matching operation is:

1. Apply the recovered mask to a binary representation of the original-ROM frame, zeroing excluded pixels.
2. Pack each group of eight pixels least-significant-bit first, retaining the full 512-byte frame footprint.
3. Apply zero-seed Jenkins one-at-a-time hashing.
4. Look up the resulting 32-bit tag and follow its pointer.

All twelve starts match, each through two shade-derived binary representations. Both matches per mode lead to the same legacy colour map. **All 24 tags also occur in all three IJ CHROMA sections.** This was an exact lookup; no fuzzy image threshold or manual hash selection was used. The tested hypotheses, including representations that produced no hits, are retained in `colordmd-firmware/probe/jenkins-probe.json`.

These tags are game-specific visual identities, not semantic event labels. We know their mode names because the input frames came from controlled, labelled emulator scenarios. The colour-map collection does not by itself tell us which player is active, when a mode started, or whether repeated frames constitute another event.

## Legacy colour-map decoding

The recovered legacy encoding reads MSB-first nibbles. A short token stores a run length minus one in a nibble below 8, followed by the colour index. An extended token uses the first nibble's low three bits and the next nibble for a seven-bit run length minus one, then a colour index. This recovers 128×32 maps of four-bit colour indices.

Validation is unusually strong for an inferred format: **all 1,599 pointed-to maps produce exactly 4,096 pixels; no run crosses a 128-pixel row; all 1,598 adjacent stream boundaries match after 16-byte alignment; the final file tail is zero padding.** Each original index image and decoded hash is retained. The 1,599 records contain 1,239 distinct decoded index arrays; duplicate arrays at separate addresses are preserved for provenance. The map count is not an event count: multiple tags can point to one overlay, and overlays cover many animation frames or partial scenes.

Four contiguous 16-entry RGB tables follow the legacy mask configuration. The viewer can preview each manually. The tag record's low byte has values beyond 0–3, so it is deliberately preserved as an uninterpreted control field instead of being declared a palette selector.

The reconstructed start images demonstrate why the maps alone are incomplete cue images. They contain coloured regions for titles, instructions and ornaments; the original game supplies the actual letters, scores and intensity. Combining a correctly matched overlay with an emulator frame produces the recognizable coloured screen. We normalize palette brightness and apply emulator shade/3 for inspection; hardware gamma, palette switching, dot geometry and temporal combination are still outside this renderer.

## CHROMA boundary and useful next steps

CHROMA's tag tables and masks are accessible, and its twelve start identities are now corroborated directly. Its compressed colour streams differ from legacy. Simple candidate decoders failed whole-map length/alignment checks, so none is presented as a working CHROMA colour decoder. The roles of its three image variants and runtime control fields also remain open. No global-encryption claim is justified: the recovered tables and legacy colour data are directly readable.

For the project, we now have manufacturer-specific recognition evidence and reconstructed reference starts for all twelve modes. The recovered masks can help guide which camera regions matter, and the legacy overlays add useful colour-reference candidates. Exact firmware hashes cannot be applied directly to ordinary camera pixels: a one-bit input difference changes the tag. Camera normalization, tolerant structural matching, title extraction, temporal event suppression and association with the already audited player turns remain the application's job.

Completing CHROMA decompression could provide more faithful reference colours without extra filming, but is not required to accept the narrower goal of mode-start identity per player. Optional statistics should be emitted when supported by observed evidence; missing mode endings need not block that work.
