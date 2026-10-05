# Cave right-edge and ceiling-crack fix status

## Current state: REVIEW_READY

- No commit, release, version, migration, seed, or collision-rule change has been made for this task.
- Ceiling-crack artwork is now mirrored into the solid roof. `LavaHazard.crack_art_geometry()` derives the glow, zigzag and branches from the surface and lane direction. `LavaHazardModel.crack_rect()` is unchanged, so lethal contact and generation contracts are unchanged.
- Cave rendering was observed through the real `MultiplayerV2Match` scene and camera in both deterministic draw captures and a separate capture with Match `_process` enabled. Across both, no intermittent blink was reproduced; no speculative renderer modification was made. This is still not a networked/live-match reproduction: the process test injects a local controlled runner pose and shared-clock sample, so it exercises Match process/camera/presentation/draw ordering but not remote transport timing.
- All self-started Godot processes have exited; the pre-existing user editor process is still running. Preserve unrelated dirty work, especially capture/pacing/menu files and the recorded death sound.

## Verification completed

- `tools/cave_crack_geometry_test.gd`: PASS. Floor and ceiling glow, main zigzag and all branches stay on the solid side and touch the surface. Existing lethal `crack_rect()` origin and depth remain unchanged.
- `tools/cave_crack_visual_test.tscn`: PASS, real GPU, seed code `GR15-100000014`. Captures use actual `main.tscn` for SP and `multiplayer_v2_match.tscn` for MP at 1280×720 and 540×960. Captures: `E:/Utveckling/Gravity Run/.codex-cave-right-edge-review/crack-captures/`.
- `tools/cave_match_right_edge_capture.tscn`: PASS, actual MultiplayerV2Match/camera/presentation, 60 Hz simulated movement at 500 px/s, fractional 8.333 px camera increments, 180 rendered frames per viewport/segment. It saved all 1,080 narrow-strip frames and 42 full context frames across 960×540 and 540×960 for cave entry, interior and exit. Per-frame canvas transform stayed on the actual 180 px player anchor.
- Right-strip changed-pixel ratio between adjacent frames: landscape p50 8.58–10.22%, p95 12.96–13.43%; portrait p50 5.72–6.64%, p95 8.25–9.92%. These are movement measurements, not a pass/fail flicker threshold. The sequence shows expected smooth parallax and the cave transition boundary moving about 8.33 screen px/frame; a transient blink was not reproduced.
- Continuous MP strips and camera metadata: `E:/Utveckling/Gravity Run/.codex-cave-right-edge-review/mp-frame-strips/frames.json` and `mp_*_*.png`; full-context frames are `mp_*_full_*.png` in the same folder.
- A headless attempt at the GPU capture timed out because its `RenderingServer.frame_post_draw` wait did not complete; only the owned test process was stopped. Successful captures were rerun non-headless on the NVIDIA GPU. Godot emitted an environment-only “Failed to read the root certificate store” message; captures and targeted test exited 0 with no script errors.

### Autonomous Match process/camera path

- `tools/cave_match_live_process_capture.tscn`: PASS on the NVIDIA GPU, with the real `MultiplayerV2Match._process` enabled and actual `RunnerCamera.follow`, `RaceCoursePresentation.set_camera_left`, world rendering and viewport canvas transform. The fixture feeds controlled 500 px/s pose samples into the shared-clock/local-pose history; physics and network transport are disabled, so this validates callback and camera/draw ordering, not a live multiplayer session or transport jitter.
- 1,080 rendered callbacks across 960×540 and 540×960, 180 frames per entry/interior/exit segment. Every callback asserted that Match camera left, presentation clip-left, and inverse applied canvas bounds agreed (maximum recorded error below 0.001 px), and that camera advanced 8.333 px per controlled frame. No callback missed, right-edge strip went blank, or intermittent cave blink was observed.
- Adjacent right-strip changed-pixel p50/p95: landscape 8.58–10.22% / 12.96–13.43%; portrait 5.72–6.64% / 8.25–9.92%. These are motion measurements, not a flicker threshold. New continuous strips, full frames, and per-callback transform/shared-clock metadata are in `E:/Utveckling/Gravity Run/.codex-cave-right-edge-review/mp-live-process/`; `live_frames.json` is the bounded measurement record.

## Review gate

Ready for root review. No live migration or Pages publication is part of this stage; this presentation-only change requires no version/API/generator bump. Cave flicker remains an unconfirmed report and is not represented as fixed: the actual Match callback/camera/draw sequence with controlled shared-clock poses did not reproduce it, while remote network timing remains untested. Proposed scoped source is `hazards/lava_hazard.gd` plus the targeted geometry/visual/draw/process capture files; `biomes/biome_renderer.gd` and all gameplay/generator contracts are unchanged. No commit or staging has been done.
