# Cave user-capture float clipping fix status

## State: RELEASE_COMPLETE

This is a shared visual-only correction based on the user capture `multiplayer_right_edge_peer1_host_1791277588.zip`. The preceding right-edge capture diagnostics remain available to collect another real multiplayer sample.

## Reproduction and cause

The extracted user capture is at `E:\Utveckling\Gravity Run\.codex-user-right-edge-1791277588\`. Its 24 valid PNGs show intermittent diagonal cutouts in the cave's top ridge layers. Metadata keeps applied/requested camera bounds within about 0.00025 px; it does not support a camera/network-stall diagnosis.

`BiomeRenderer._draw_cave_backdrop` had mixed bottom fill closure corners into the same `PackedVector2Array` later filtered as top-ridge samples. At the captured fractional bounds, float32 rounding moved a bottom corner just inside the high-precision clip interval. That corner entered the upper contour and could make its polygon self-intersect. Fill quads already create their own bottom corners.

## Fix and verification

- The shared renderer now builds/clips a top-only contour in `cave_clipped_ridge_vertices()`. Each adjacent pair is filled by its own quad, so bottom vertices cannot enter the ridge filter.
- The durable regression replays all 24 captured course-left coordinates. Each proves the old float32 conversion would admit a closure corner; all three clipped contours are strictly x-ordered and contain no bottom-fill y values.
- Actual GPU regression from exact gameplay commit `74a838b54120debfcfc9715c06c15242210b1247`: `tools/cave_user_float_clip_regression_test.tscn`, PASS (`failures=0`, exit 0), six frames at captured coordinates; owned PID 62284 exited. Evidence: `E:\Utveckling\Gravity Run\.codex-user-right-edge-floatfix\after_00_5211.718.png`, `after_01_5230.756.png`, `after_05_5307.971.png`, `after_08_5364.783.png`, `after_20_5585.014.png`, and `after_21_5603.598.png`.
- The clean exact-commit Godot import and regression test passed. The Web export was produced from that exact commit with Godot 4.7.2.
- No parallax, camera, asset, biome, API, generator, seed, gameplay, or database behavior changed.

## Published release

- Gameplay source commit `74a838b54120debfcfc9715c06c15242210b1247` was pushed to Azure `codex/current-prototype`.
- Pages commit `7e8fddfc63206a9d99aba1554f134efa1bc2819c` was pushed to `main`; deployment workflow `37443199013` completed successfully at that head.
- Root and game markers and the normal loader use build ID `right-edge-capture-floatfix-74a838b-20261006`.
- Public loader returned HTTP 200 and references the versioned PCK. Public PCK: 3,357,752 bytes, SHA-256 `865EFA26EDDD1F55DFE0A9C27301D76A86FEBCB55258875462BE161C4025B934`, matching the clean local export exactly.
- No database migration or protocol/generator version change was made.

## Limits

The fix was verified through the shared renderer on the actual GPU at the user's recorded fractional camera positions, and the new Web bundle is live. A fresh authenticated/networked multiplayer capture at those same positions has not yet been collected; the existing MP diagnostics capture remains available for that validation. The original capture does not establish a network fault.
