# Ghost render interpolation root review

Status: ROOT_APPROVED, 2026-10-07. Presentation-only correction for measured user-trace sawtooth.

Root reviewed shared GhostHazard presentation pose/phase, disabled native double interpolation, SP camera-aligned fractional tick and MP world render payload. Hitbox/swept collision, activation snapshot and integer authoritative phase remain unchanged. Root independently ran ghost_render_interpolation_test.tscn: exit0, failures0, seed100000030. User trace has820 same-tick backward pairs median-2.104px; bounded actual-main GPU240Hz fixture reports396 same-tick forward pairs median+0.9165px.60Hz and uneven delta captures pass. Controlled SP fixture and MP integration test are not a connected browser MP proof.

Approve scoped render source/test/report hunks, no API/gen/DB migration. main.gd only camera-aligned render-hook hunks; exclude unrelated historical capture/pacing edits. Preserve approved audio/input/touch/cave. Publish clean exact-commit Web/Pages; root independently verifies workflow exacthead, both BUILD_ID/loaders and downloaded public PCK hash before completion.
