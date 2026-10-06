# Approved gravity flip tone

User approved the inline `gravity-flip-tonal-layer.wav` preview: “perfekt!! exakt så! den tar vi”.

Root copied the exact preview to the existing shared SP/MP asset `assets/audio/sfx/gravity_flip.wav`. SHA-256: `3E6A9AE636B4DA53BA625E49B79342D0A76726A40260F3929D94D65B06FBDFD5`. It is PCM16 mono 44,100 Hz, 12,348 frames, 0.28 seconds.

The original generator was first reconstructed and matched every sample of the former WAV. Only its simultaneous deterministic `0.3 * air` layer was removed. The tone's phase, envelope, length and original gain reference are retained. `tools/audio/generate_sfx_previews.py::flip` now produces the approved PCM exactly; root independently verified byte-for-byte equality without regenerating other sound assets.

ROOT_APPROVED scope: this WAV and its generator function, exact-commit import/SFX check/Web export, Azure and Pages release. No gameplay, routing, volume settings, death audio, generator/API version or database changes. Preserve all unrelated uncommitted work. This is the user's selected sound replacement, not a fix for unverified mobile audio latency/stalls/coin behavior.

## Publication verified (2026-10-06)

- Source implementation commit: `0a7c016d5df35a09080d923f78f8ed50c789e24e`; build metadata commit: `7e6062d3272f1085dd12e336c4fc87b86b5eda61` (`config/version=2026.10.06-flip-tone-0a7c016`). Azure branch `codex/current-prototype` is at the metadata commit before this documentation-only follow-up.
- Pages commit: `72e15fe66042367ca532a15b6e68bd02b675d73e`; workflow [37509644973](https://github.com/hjelmdev/gravity-run/actions/runs/37509644973) completed successfully for that exact head.
- Public build ID in root and game `BUILD_ID`: `flip-tone-0a7c016-20261006`. Root and loader HTTP 200; loader selects `index.flip-tone-0a7c016-20261006.pck`.
- Local and public pack: 3,464,608 bytes, SHA-256 `08FF60D4945519462392CD4BC2EB1A0C6DCD5352A93E16EA2C67FD9A156CA489`; public download HTTP 200.
- Clean archive of exact build commit `7e6062d`: Godot import PASS and `tools/sfx_shared_pool_test.tscn` PASS (`failures=0 starts=4`), processes exited normally (import PID 33328, test PID 33644). No game/API/gen/database migration changes.

Root independently verified the exact successful workflow head, both public BUILD_ID files and both loaders (HTTP 200), Azure remote head, and downloaded public PCK byte count/hash matching the clean metadata-commit export. The selected shared SP/MP sound is published; unrelated device latency/stall/coin investigations remain unchanged.
