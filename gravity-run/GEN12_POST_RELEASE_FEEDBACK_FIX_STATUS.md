# Gen12 post-release feedback fix status

Updated 2026-10-05. **Phase: scoped source staged; SP generated-spike propagation verified. Release build and live migration/publication remain pending.**

## Baseline and scope

- Starting source baseline: Gen12 / manifest 6 / API `2.1.20261005.8`, gameplay commit `40b7c1d`, public build `biome-risk-gen12-40b7c1d-20261005`.
- Plan scope: irreversible barrel gap falls plus a supported generated spiked-barrel/block meeting; restore the reviewed cave triangulation fix omitted from the Gen12 clean release; diagnose delayed multiplayer SFX and fix only proven local-presentation timing/dedup defects.
- Existing unrelated working-tree edits include capture/pacing/menu changes and the selected death audio. Preserve them. `systems/hazard_interaction_rules.gd` and `tools/barrel_motion_test.gd` already contain root's uncommitted downward-crossing fix and must be retained.

## Initial findings

- The downward-crossing barrel motion regression is implemented locally. A Gen13-only support corridor now prevents future floor gaps from crossing the actual first-chain barrel spawn-to-block-circle-impact path. This fixes the former seed `100000003` encounter without changing Gen12 output; the test queries canonical `CourseSurfaceIndex` support along the path and checks deterministic 45k/100k course prefixes.
- The release tuple is staged locally as generator 13 / multiplayer API `2.1.20261005.9` / build `2026.10.05-gen13-barrel-gap-recovery`, with draft migration `202610050002_generator13_gap_safe_barrels.sql`. The migration is not applied. Old Gen12 and Gen11 support gates are retained.
- Frozen Gen12 identity verification covers both manifest hashes and independent collectible row hashes for five seeds from the clean published `40b7c1d` archive. All five manifest/coin fixtures pass under the new source. Gen11 fixtures also pass.
- `biomes/biome_renderer.gd` includes the cave triangulation correction omitted from the clean Gen12 release. The shared `BiomeRenderer.draw_backdrop` path used by both `main.gd` and `race_course_presentation.gd` rendered on NVIDIA OpenGL at distances 4799/4800/4801 and 9599/9600/9601 without invalid-polygon/render errors. Captures are in `.codex-biome-feedback-review/cave-boundary-*.png`; the repeatable capture runner is `tools/biome_cave_backdrop_gpu_capture.gd`.
- MP event-path inspection confirms accepted local flips and predicted coin effects are local; a lethal barrel stops the runner in `pending_barrel` and waits for host validation before death SFX. Added bounded timestamps for barrel contact, authoritative terminal commit/report, and actual local death-SFX start so diagnostics can distinguish local presentation, host, and audio delay. No SFX authority/timing behavior was changed. The reported delayed effect is not yet identified/reproduced in an authenticated match; no user clarification arrived, so this remains diagnostic-only.

## Verification / release

- Passed locally: `generator_v12_freeze_test.gd` (five manifest plus five collectible hashes), `generator_v11_freeze_test.gd`, `generator_v8_compatibility_test.gd`, `course_generator_test.gd`, `course_manifest_test.gd`, `spiked_barrel_shared_simulation_test.tscn` (seed `100000003`, canonical support, block break, continued rolling, baseline/replay and lethal dedup), `barrel_motion_test.gd`, `singleplayer_spiked_barrel_runtime_test.tscn` (now also proves a generated seed event reaches `is_spiked` through `main._spawn_course_event`), `biome_risk_generation_test.gd` (existing eight-seed Gen12 risk suite; six route fixtures at 250/500/750), `biome_backdrop_anchor_test.gd`, and `release_version_contract_test.gd`. Actual main and MP match scene startup also parse/load headlessly without script errors.
- Godot headless emits environment warnings about the user log directory and Windows certificate store; test runners exit 0 with their PASS summaries. These are not source parse or gameplay test failures.
- New generator/API gates are drafted, but migration `202610050002` has not been dry-run or applied. Root review is required before release. Its diff from `202610050001` is limited to adding the Gen13/.9 create-room, coin-round and receipt generator gates while retaining Gen11/12 tuples.
- Six actual OpenGL cave-boundary captures were produced with the shared backdrop renderer. They validate rendering across the precise theme-fragment boundaries but are not captures of an authenticated live MP match. A headless pixel-capture test is unavailable because Godot's dummy renderer returns no texture; the non-headless OpenGL capture succeeded.
- Root approved the scoped release after review of the generator, version gates, cave correction, migration scope, and independent tests. The final SP event-to-scene flag propagation is now covered by an actual main-scene test. No live migration, Azure push, or Pages publication is recorded until those steps are verified.
