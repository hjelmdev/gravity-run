# Ghost render interpolation root review

Status: ROOT_APPROVED, 2026-10-07. Presentation-only correction for measured user-trace sawtooth.

Root reviewed shared GhostHazard presentation pose/phase, disabled native double interpolation, SP camera-aligned fractional tick and MP world render payload. Hitbox/swept collision, activation snapshot and integer authoritative phase remain unchanged. Root independently ran ghost_render_interpolation_test.tscn: exit0, failures0, seed100000030. User trace has820 same-tick backward pairs median-2.104px; bounded actual-main GPU240Hz fixture reports396 same-tick forward pairs median+0.9165px.60Hz and uneven delta captures pass. Controlled SP fixture and MP integration test are not a connected browser MP proof.

Approve scoped render source/test/report hunks, no API/gen/DB migration. main.gd only camera-aligned render-hook hunks; exclude unrelated historical capture/pacing edits. Preserve approved audio/input/touch/cave. Publish clean exact-commit Web/Pages; root independently verifies workflow exacthead, both BUILD_ID/loaders and downloaded public PCK hash before completion.

## Independent root live verification

Workflow37675256822 completed/success at exact Pageshead9b0fbdcfd009f8978d3fbe8f0e9728e650f88d6d. Both publicBUILD_ID markers/rootloader HTTP200 match shared-ghost-render-934e5a6-20261007. Gameloader HTTP200 selects index.ghost-render-934e5a6-20261007.pck. Root independently downloaded publicPCK:3,629,864bytes SHA2569423F1D0B5EAA404BFA3852E21EECFCD5BF641EC86DAAACD4618904847ED6E39 identical to cleanexport. Azure remote verified70b63d58d1a470ca4d1fdc4265b3d1a2b081f8b1, gameplay934e5a6294b1ecb43814d68ff747b9c848392e10. Releaseverified; no liveconnectedMP gameplayclaim. Follow-up paused after completion.

