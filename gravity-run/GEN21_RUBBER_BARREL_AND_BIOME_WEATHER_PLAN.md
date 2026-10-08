# Gen21: rubber barrel and biome weather

Status: approved by the user on 2026-10-08 for implementation and review. Floating mid-course platforms are a later, separate decision after this package is played.

## Scope

1. Add one visibly distinct rubber barrel encounter to free-run generation. Its defining interaction is a deterministic bounce/change of direction when it hits a block or solid step: neither the barrel nor the struck obstacle is destroyed by that interaction. Keep player contact lethal, make the new movement readable, and prove there is a reachable opposite-lane route. Preserve the ordinary and spiked barrels' existing interactions and frequencies in older seeds. Choose a bounded bounce rule that produces a meaningful player encounter instead of an offscreen object that never returns; document the exact rule and why it is fair. Treat gaps, spikes, slope support, repeated contacts, and offscreen lifetime explicitly.
2. Add subtle, visually distinct weather/atmosphere to the existing biomes, using the shared backdrop renderer in both SP and MP. Candidates: drifting frost in the ice/cave theme, wisps or fog in haunted, embers/ash in lava, and sparse sparkle/wind in classic. Keep hazard silhouettes, coins, warnings and UI legible. Use deterministic, bounded drawing based on course/world position and presentation time; avoid per-frame texture/node creation, edge popping, biome-boundary flicker, and the former cave right-edge clipping failure. Keep these as replaceable presentation layers for future hand-drawn tiles.

## Compatibility and correctness

- Version new generated hazards as Gen21 with the matching API/manifest and reviewed migration only if the published backend contract requires it. Freeze Gen17–20 seed output, current wallet/coin awards, and Gen20 ordinary/spiked barrel behavior. Do not introduce a separate MP generator or client-only hazard decision.
- Carry rubber-barrel identity and bounce state through the shared model, snapshot/baseline/retry/spectator path and both presentations. SP and MP must agree on tick, contact surface, position and interaction result. Do not infer rubber behavior from color alone.
- Run full-manifest RunnerMotion safe-route checks at 250/500/750 px/s on representative seeds and encounter phases; compare bounded generation density and rubber encounter reach to Gen20. Test no repeated collision/destruction loops or unbounded render/physics work.
- Capture actual GPU SP and started MP match-scene views plus a short moving sequence across biome boundaries, including the right edge and portrait width. Static screenshots alone cannot establish absence of flicker. Inspect the visuals before release.
- Preserve all unrelated dirty hunks, especially ongoing frame-pacing/capture work in `main.gd`, `tools/singleplayer_render_capture.gd`, `ui/main_menu.gd`, and prior review notes. Use scoped staging and a clean exact-commit test/export; own Godot/helper processes must be time-bounded and cleaned up without touching the user's editor.

## Handoff and release

Luna implements and records evidence in a companion STATUS file. Root reviews actual diff, interaction semantics, SP/MP parity, legacy freezes, safety routes and moving visuals, and requests concrete corrections before approving. Then scoped Azure push, only necessary reviewed Supabase migration after linked-history check, clean exact-commit Web export and Pages-root publication. Root independently verifies workflow exact head/success, both BUILD_ID files, loaders and downloaded public PCK hash. Report remaining limitations plainly; do not claim a connected MP browser test from an offline scene fixture.
