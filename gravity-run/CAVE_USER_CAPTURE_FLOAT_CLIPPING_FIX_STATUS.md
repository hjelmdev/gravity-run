# Cave user-capture float clipping fix status

## State: REVIEW_READY — not yet committed or published

The prior right-edge diagnostics release is complete: source capture commit `8278c35` is on Azure and Pages commit `8140f42` is live. This is a separate minimal visual follow-up based on user capture `multiplayer_right_edge_peer1_host_1791277588.zip`.

## Reproduction and cause

The extracted user capture is at `E:\Utveckling\Gravity Run\.codex-user-right-edge-1791277588\`. Its 24 valid PNGs show intermittent diagonal cutouts in the cave's top ridge layers. Capture metadata keeps applied/requested canvas bounds within about 0.00025 px; it does not support a camera/network-stall diagnosis.

`BiomeRenderer._draw_cave_backdrop` mixed bottom fill closure corners into the same `PackedVector2Array` later filtered as top ridge samples. Packed points are float32; at the capture's fractional bounds, a bottom corner rounded just inside the high-precision clip interval and entered the upper contour. This can create a backwards/self-intersecting contour. Fill quads already create their own bottom corners.

## Fix

- The shared renderer now creates and clips a top-only ridge contour through `cave_clipped_ridge_vertices()`; each adjacent contour pair is filled with its own independent quad. Bottom fill vertices never enter the upper contour filter.
- No parallax, camera, asset, biome, API, generator, seed, gameplay, or database behavior changed.

## Verification

- New durable regression test replays all 24 user `course_left` fractional positions at logical 960×540. For each position it confirms the old float32 conversion would admit a bottom corner, then asserts all three rendered ridge contours are strictly x-ordered and contain no bottom-fill y values.
- Actual GPU-renderer test: `tools/cave_user_float_clip_regression_test.tscn` — PASS, `failures=0`, exit 0; bounded owned PID 51560 exited normally. GPU/OpenGL: NVIDIA RTX 5070 Ti.
- Six post-fix viewport PNGs at user frames 0, 1, 5, 8, 20 and 21 are saved under `E:\Utveckling\Gravity Run\.codex-user-right-edge-floatfix\`. Examples: `after_00_5211.718.png`, `after_01_5230.756.png`, `after_20_5585.014.png`. They render the same shared cave backdrop at the exact capture camera/course coordinates; no diagonal cutouts are visible.
- The pre-fix user evidence remains available in `.codex-user-right-edge-1791277588/contact_sheet.png`; no new Web capture has been run yet.

## Scope and next step

Only `biomes/biome_renderer.gd`, the new geometry/GPU regression scene and script, and this status document belong to this follow-up. All existing unrelated dirty files, including `main.gd`, capture instrumentation, menu and pacing files, remain unstaged. Root review is requested before a follow-up commit, exact-commit Web export, and Pages publication. No migration or version gate is needed.
