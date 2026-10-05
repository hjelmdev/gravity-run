# Gen13 post-release feedback status

Updated 2026-10-05. **Phase: RELEASE_COMPLETE.**

## Delivered

- Fixed spiked-barrel gap recovery with Gen13-only corridor placement, retaining Gen12 and older generation output. API is `2.1.20261005.9`, generator 13, visible build `2026.10.05-gen13-barrel-gap-recovery`.
- Restored the reviewed cave triangulation correction. The shared cave renderer now draws clipped ridge segments without the invalid polygon at biome boundaries.
- Preserved the selected `death.mp3` and all unrelated capture, menu, and pacing edits; those working-tree hunks were not included in the source commit.
- Added bounded multiplayer timing diagnostics for local barrel contact, authoritative terminal report, and local death-SFX start. This release does **not** fix or claim to have reproduced the reported delayed multiplayer SFX; authenticated live-match audio timing remains open.

## Verification

- Generator seed `100000003` uses canonical `CourseSurfaceIndex` support to check the spiked-barrel/block corridor, continued barrel movement after block destruction, baseline/replay, and lethal deduplication.
- `singleplayer_spiked_barrel_runtime_test.tscn` passes through actual `main._spawn_course_event`: a generated Gen13 event reaches the real spawned barrel scene with `is_spiked=true`.
- Gen12 frozen manifest and collectible hashes (five seeds), Gen11 and Gen8 compatibility, release-version gates, barrel motion, course generator/manifest, and the existing bounded Gen12 risk-route suite pass. Root independently ran the Gen13 shared simulation and Gen12 freeze checks.
- The exact source commit was archived to `E:/Utveckling/Gravity Run/.codex-gen13-clean-5983a19`; after Godot import, the SP generated-spawn test, Gen12 frozen fixture test, and release-version contract test all passed there. The first pre-import archive launch is disregarded because the clean copy had not generated Godot's import/class cache.
- Six NVIDIA OpenGL captures across cave boundaries 4799/4800/4801 and 9599/9600/9601 showed no invalid polygon/render errors. Headless pixel capture remains unsupported by Godot's dummy renderer.

## Release evidence

- Azure source branch `codex/current-prototype`: commit `5983a19470a6f0246675eb430c844df909510207` (`Fix Gen13 spiked barrel gap recovery`), pushed to the verified Azure origin.
- Supabase migration `202610050002_generator13_gap_safe_barrels.sql` was the only pending migration in the dry-run. It was applied; the subsequent linked history lists `.002` on both local and remote. Its SQL only extends the version gates for Gen13/API `.9`, retaining the Gen11/12 tuples and existing authorization behavior.
- Pages `main`: commit `84fdfbdc808c98b41f2f42e8b9738293109d910f`, pushed to `https://github.com/hjelmdev/gravity-run`. The active bundle remains `docs/game/`; both `docs/BUILD_ID` and `docs/game/BUILD_ID` are `gen13-gap-safe-barrels-5983a19-20261005`, and the root loader points to that bundle.
- GitHub Pages workflow `37276367935` completed successfully for commit `84fdfbdc808c98b41f2f42e8b9738293109d910f`.
- Public PCK: 3,146,256 bytes, SHA-256 `B84FF10DEFD09EB0CAE0B4D558476A092012CCE7BDCA555D1A1B14398CB1BE87`, matching the clean local export.

Public game: https://hjelmdev.github.io/gravity-run/