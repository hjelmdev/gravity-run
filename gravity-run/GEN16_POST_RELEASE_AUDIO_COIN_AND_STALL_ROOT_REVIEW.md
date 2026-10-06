# Gen16 audio, coin and stall feedback — root review

Status: ROOT_APPROVED for the scoped offscreen audio correction and opt-in diagnostics release, pending clean exact-commit verification and publication. The user's delayed audio, missed coin and intermittent stall remain unresolved.

Published baseline: gameplay `80d2e44025cc7e98001104607f4cfc6ac9703118`, build `ghost-gen16-density-biome-80d2e44-20261006`.

## Confirmed scope

The real SP barrel/block probe reproduces an offscreen barrel destruction sound. The shared camera-range helper removes that SP/MP presentation discrepancy. No duplicate accepted gravity flip, missed coin, multi-second browser audio delay or actual frame stall has been reproduced. Native event-start tests are not audible output timing measurements. No audio assets, wallet rules, generator/API version or database migration should change for this scoped checkpoint.

## Review and required corrections

- Initial SP audio mode forced an unrelated Gen4 demo seed. Corrected mode must preserve real user-selected/free-run seed, ruleset and controls and export actual metadata.
- Audio-only capture must avoid render-detail collection, image readback and continuously running browser observers. MP contact diagnostic dictionaries must only be built when capture is active.
- MP audio-only capture and normal diagnostics JSON export were tested through the real overlay with a rendered Godot run; screenshot readback remains zero for that path. Separate screenshot capture contract also passed with a renderer. These are Luna's test results, not mobile WebAudio output verification.
- SP diagnostics currently reuse roughly 146 lines of unrelated uncommitted frame-pacing fixture code. Root requested an independent small audio-only capture helper and minimal main-scene seams so those older dirty hunks are preserved and excluded from staging/publication.
- MP audio capture should close its diagnostic overlay and cancel the initiating touch/pending gravity input, allowing actual gameplay during the capture. Root requested a regression for this lifecycle.

Actual exported `out/index.js` was inspected: the private `GodotAudio.ctx` is created using `new (window.AudioContext || window.webkitAudioContext)(opts)` with sample-rate options and no explicit latency hint. It is not directly exposed to GDScript. An opt-in pre-engine constructor hook could observe the actual context without creating another context, but no such browser timing measurement is claimed here.

## Acceptance still required

Inspect corrected scoped diff, verify independent SP audio-only report and seed metadata, normal disabled overhead and MP touch lifecycle. Run required clean exact-commit tests/export before Azure/Pages publication. Preserve all unrelated dirty hunks, recorded death audio, touch fix, cave fix and existing capture feature. Independently verify workflow head, both BUILD_ID files, loaders and downloaded public PCK hash after publishing. User-device audio/output and intermittent coin/stall behavior remain open until evidence is obtained.

## Final scoped source approval (2026-10-06)

Root inspected the staged 18-file diff and the reconstructed 44-line main-scene change. The older uncommitted render/pacing fixture and blocked-state diagnostic changes remain unstaged. SP audio capture now uses its own child helper, refuses menu demo scenes, preserves the active seed/version and runs only when explicitly requested. SP callback/coin hooks use that same child. MP capture closes the diagnostics overlay, resets the initiating gesture and pending gravity input, stops after its bounded timer and exports via the existing JSON diagnostics flow. Normal gameplay creates no SP capture child or diagnostic dictionaries.

Luna's final actual-main SP test, SFX pool test and MP handler/export integration test pass. The MP test explicitly reports `MP_AUDIO_TOUCH_DISPATCHED=false` in the native headless fixture, then tests the connected button signal/handler separately; root does not treat this as a real mobile GUI activation proof. Standard button wiring and bounded handler behavior are acceptable for this diagnostic release, with the limitation retained. The earlier renderer-based ZIP contract passed and no audio-only capture performs image readback. No audible mobile output timing, target-device frame-stall cause or missed-pickup fix is claimed.

Approved next steps: scoped source commit/Azure push, clean archive of that exact commit, required targeted tests and Web export, Pages root/game publication and independent public identity/hash verification. No migration is needed because API/generation/wallet contracts are unchanged.
