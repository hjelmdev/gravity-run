# Lava, rhythm and single-player replay status

Updated 2026-10-05. **Phase: ROOT_APPROVED; scoped commit and release in progress.**

## Scope and compatibility

- Baseline: HEAD `8009c472ee73453d0d6dd1dec1d73ebb6fe3121f`, API `2.1.20261005.9`, Gen13, manifest6. Current working-tree target is API `.10`, Gen14, manifest7, visible build label `2026.10.05-gen14-lava-seed-replay`.
- Five pre-change Gen13 manifest/event/coin hash fixtures remain byte-identical via `tools/generator_v13_freeze_test.gd`.
- Gen14's encounter mix overlays lava weights over the Gen12 cave/haunted table, preserving cave rocks/saws/spikes and haunted ghost weight. Gen13 and earlier use their existing rules and do not receive lava or Gen14 rhythm.
- Migration `supabase/migrations/202610050003_generator14_lava_rhythm_seed_replay.sql` is pending live apply after a linked-history check. Its release gates are API `.10` + Gen14; existing Gen11–13 tuples and receipt behavior remain. Three migrations `.001`–`.003` and `tools/lava_gen14_release_gate_test.sql` passed in an isolated local PostgreSQL clone under `SET ROLE authenticated`; the existing auth shim does not emulate live GoTrue/PostgREST.
- Pre-existing dirty `main.gd`, menu, pacing, capture, audio, and unrelated files are excluded from this scoped commit; only the reviewed lava/gameplay hunks of `main.gd` are staged.

## Review findings addressed

- Gen14 now has a deterministic three-phase spacing pattern (two closer encounter intervals followed by a longer recovery) with a 1.22 baseline spacing scale so the rhythm does not silently cause a large density increase. Five 45,000px seeds measured a Gen13 mean dynamic-event gap of 913.2px and a Gen14 three-phase mean of 816.9px (-10.5%); Gen14 short phases averaged 757.8px and recovery 935.0px. This is a bounded cohort, not a proof for every seed.
- Lava crack validation checks the original payload value is a bool before conversion. The negative malformed-type test passes.
- Volcano validator limits width/height/projectile envelope and requires at least a 300px floor-ceiling corridor plus 24px clearance above the ceiling RunnerMotion body for the worst allowed apex. The unsafe `v=700,g=900,r=18` payload is rejected. Paired projectiles originate at the visible crater sides; the shared rendered volcano polygon is also the lethal body geometry.
- The shared-world route test uses the full generated manifest, not an isolated one-event world, for both a volcano and a crack. It advances real RunnerMotion at 250/500/750px/s, checks no intervening terminal collision, and confirms support on the chosen safe surface. Separate isolated contact tests remain for exact/shared collision assertions.
- Ordinary seed input is routed through `ChallengeService`; challenge-code parsing and ordinary-seed parsing remain separate validation paths there. No shared parser helper was extracted. The active challenge UI hides/disables ordinary seed entry, and calling start cannot replace that challenge seed/version.
- Full-manifest volcano-route tests now initialize `WorldSimulation.tick/elapsed` from eruption activation tick minus the player's travel time to the event, then sample multiple offsets spanning launch, active projectile lifetime, and the eruption period at 250/500/750 px/s. The route cohort verifies active-projectile coverage rather than passing only in the no-projectile phase.
- Risk-coin placement now uses `LavaHazardModel.volcano_collision_envelope()` for the same crater source, projectile apex, lifetime, and radius used by the shared hazard model. A maximum-allowed volcano fixture checks the envelope includes the corrected apex and excludes a coin there while leaving the supported ceiling coin lane clear.
- The actual SP capture fixture now selects resolver-accepted events, runs the public seeded-run path, spawns the ordinary event stream and actual terrain, and asserts the hazard surface matches supported terrain. It does not teleport an event over absent terrain.

## Verification run

- `tools/generator_v13_freeze_test.gd`: PASS, failures=0, five frozen hashes unchanged.
- `tools/lava_generation_contract_test.gd`: PASS, seeds 100000003, 100000014, 100000042, 100000777, 100000918 at 45k px. Latest run: Gen14 946 coins vs Gen13 872 (+8.5%); 24 voluntary risk rows; 12 cracks and 3 volcanoes. Gen13 mean gap 913.2px, Gen14 cycle mean 816.9px, short phases 757.8px, recovery 935.0px. The seed cohort is targeted and small; it does not establish all-seed fairness.
- `tools/lava_shared_world_test.tscn`: PASS, failures=0, generated seed100000014 contains both lava types; shared presentation/world tick, scene/model projectiles, body/projectile/crack contacts, isolated routes, and full-manifest routes at 250/500/750 are checked. For each tested volcano speed, route start tick is aligned to the selected eruption phase; phase offsets sample the launch edge, active-lifetime interior/edge, and period edge. At least one actual projectile is observed in the event band at every tested speed.
- `tools/course_manifest_test.gd`, `tools/course_generator_test.gd`, `tools/challenge_service_test.gd`: PASS. Manifest validation rejects malformed `from_ceiling` and a ceiling-unsafe volcano payload.
- `tools/singleplayer_seed_replay_integration_test.tscn`: PASS. Covers invalid input, frozen Gen13 `GR13-100000003`, active challenge seed immutability, valid numeric seed, blank/random run, current `GR14-100000014`, actual main.tscn lava spawn, SP-to-MP resolved event geometry, replay identity/reset, and a fresh random run.
- `tools/multiplayer_v2/release_version_contract_test.gd`: PASS for API `.10`/Gen14/project label/draft gate.
- `tools/touch_gesture_lifecycle_test.tscn`: PASS, failures=0.
- Actual OpenGL captures from `main.tscn` are in `E:/Utveckling/Gravity Run/.codex-lava-review/`: `lava_sp_lava_crack_landscape.png`, `lava_sp_volcano_landscape.png`, `lava_sp_lava_crack_portrait.png`, `lava_sp_volcano_portrait.png`. They use ordinary seeded Gen14 `GR14-100000918`, actual spawned terrain/events, and assert support/y values (crack and volcano floor both resolved at y=496 in this seed). The volcano lies near a biome boundary, visible in the composition. Portrait retains substantial empty space; no portrait camera redesign was in scope. These are SP captures, not a connected MP match; shared MP manifest/world/presentation is covered by headless scene tests.
- Own Godot test processes were run with explicit waits and exited. The existing user editor was not touched. This restricted user profile produces environment-only `user://logs` and system certificate-store errors; assertion suites returned exit0. Some headless processes also print shutdown resource-leak notices.

## Current handoff

Root approved the reviewed implementation. The scoped source commit and backend migration are the next release steps; a clean exact-commit Web build and Pages publication follow after backend history verifies the gate.
