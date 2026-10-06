# Web right-edge PNG capture status

## State: REVIEW_READY

The bounded capture, multiplayer diagnostics-menu integration, native scene tests, and actual Web download/package check are complete. This is ready for root review. No commit or publication has been made.

## Implementation

- Added reusable `systems/multiplayer_v2/v2_right_edge_capture.gd`. Capture is opt-in and performs no GPU readback while inactive. It samples after `RenderingServer.frame_post_draw`, serializes one readback at a time, keeps only the rightmost 240-pixel strip, and releases each full viewport image immediately.
- Capture is bounded to one second, at most 30 frames, at least 33,334 microseconds between readbacks, 24 MiB retained raw pixels, and a 28 MiB ZIP. The effective frame cap is recalculated against the actual readback dimensions as well as the logical viewport dimensions; capture stops with a visible cap status instead of retaining excess pixels.
- PNG encoding and ZIP writing occur after the burst. The package contains numbered PNGs and `metadata.json`. Metadata includes build/API, seed/generator/manifest, session role/peer/round, callback and frame indices, timing/readback/crop data, viewport/strip bounds, shared and presentation ticks, requested and applied camera/canvas bounds, clip bounds, biome fragments, and bounded cave-ridge samples. No tokens, credentials, or coin data are captured.
- Added localized Start, Cancel, Save ZIP, Clear, and status controls to the MP diagnostics menu. Starting closes the overlay. A compact cancel control remains reachable outside the captured right strip. Focus loss, round change, scene exit, and explicit cancel release image buffers. The existing JSON diagnostics export is unchanged.
- The cave ridge metadata now calls the same `BiomeRenderer.cave_ridge_diagnostic_samples()` helper used by `_draw_cave_backdrop`, including the renderer's `0.16 + 0.07 * layer` parallax, clipped-fragment offset, and endpoint width. This keeps diagnostic last-vertex values aligned at narrow biome fragments.
- Cap UI status now reads the capture component's structured `completion_reason` (`raw_image_budget`) rather than matching an English message. The reason is also written into package metadata.

## Current-tree verification

- Actual GPU-rendered Godot 4.7.2 run of `tools/multiplayer_v2/right_edge_capture_contract_test.tscn`: PASS, exit 0, 29 frames. In addition to the earlier checks, it verifies all three ridge layers against the renderer helper at a 1-pixel clipped fragment. Log: `E:\Utveckling\Gravity Run\.codex-web-capture-review\native-contract-reviewfix.stdout.log` and `.stderr.log`.
- Actual GPU-rendered Godot run of `tools/multiplayer_v2/right_edge_capture_match_integration_test.tscn`: PASS, exit 0. It instantiates the real MP match scene and dispatches viewport touch input to Start/Cancel. It also sets the structured raw-budget reason and verifies the Swedish cap notice appears even when the supplied state message is localized. Log: `E:\Utveckling\Gravity Run\.codex-web-capture-review\mp-integration-reviewfix.stdout.log` and `.stderr.log`.
- A headless attempt did not produce `frame_post_draw` callbacks on this machine and therefore timed out its rendered-frame assertions. The passing runs used the actual desktop renderer in hidden, bounded Godot processes; their owned PIDs exited. This is an environment/render-path distinction, not a passing headless result.

## Actual Web download and package evidence

- Rebuilt the temporary Web fixture from the current production capture component and served it locally at `http://127.0.0.1:8764/index.html`. The served fixture PCK matched the export: 3,546,040 bytes, SHA-256 `6B5FE6B157F50D9B122F0C82E7727D04AAEF601F1BF73E55CDCA27CE9CA2D91C`.
- In isolated Chrome 153, clicked Start and then Download ZIP. DevTools reported `Browser.downloadProgress` with `state="completed"`; there were no JavaScript exceptions. Browser event log: `E:\Utveckling\Gravity Run\.codex-web-capture-review\browser-reviewfix-final.stdout.log`.
- Downloaded file: `E:\Utveckling\Gravity Run\.codex-web-capture-review\downloads-current\multiplayer_right_edge_peer1_host_1791272475.zip`, 22,678 bytes, SHA-256 `6F3A87B1C921524A15371FCB4488CF70BC73F61A9DCDD9BF98BC511D27667399`.
- Direct archive validation passed CRC, 27 entries, 26 PNG decodes and dimensions matching metadata; `completion_reason` is `complete`. Captured viewport was 1280×720; strip bounds were `[1040, 0, 240, 720]`. Retained raw data was 17,971,200 / 25,165,824 bytes; PNG payload 65,474 bytes; ZIP 22,678 / 29,360,128 bytes. Readback time was 6.9–13.7 ms, frame intervals 35.6–49.8 ms. Full validation output: `E:\Utveckling\Gravity Run\.codex-web-capture-review\package-validation-reviewfix-final.json`; the downloaded-frame preview is `E:\Utveckling\Gravity Run\.codex-web-capture-review\fixture-web-after-burst-current.png`.
- Chrome's WebGL driver logged a GPU `ReadPixels` stall during the opt-in capture; there were no JavaScript exceptions. Readback and interval metadata expose this overhead so it is not mistaken for the original flicker.

## Limits and review scope

- The package contains Godot viewport pixels, not compositor or monitor capture. The actual Web package check proves the browser download path and archive validity; it does not reproduce or diagnose the cave flicker itself.
- Browser download testing used a rendered capture fixture with the production component. The actual MP diagnostics controls were tested in the real MP match scene with native viewport input; no signed-in or networked multiplayer round was run.
- The component is reusable by SP, but only the MP diagnostics UI is wired in this change. No gameplay, network protocol, API, generator, database, or version-gate changes were made.
- Current-tree source/test changes are not committed or published. Temporary browser fixture, ZIP, logs, and screenshots are under `E:\Utveckling\Gravity Run\.codex-web-capture-review\` and are review evidence, not gameplay assets.
- Owned Godot test processes exited. The isolated Chrome and HTTP preview server were stopped after validation. The user's editor and unrelated dirty files were left untouched.
