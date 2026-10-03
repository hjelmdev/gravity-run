# Root review: shared scenes, biomes and saw

Status: **ACCEPTED FOR SCOPED RELEASE**, 2026-10-03. The corrected candidate may be staged, committed, exported from that exact clean commit, migrated and published through the authorized Azure/Pages route. Preserve unrelated dirty work.

Final staging review found and corrected an additional SP endpoint mismatch: `_physics_process` now calls `_saw_endpoint_impact`, using active/removed-aware shared circle contact. Root inspected the corrected staged path and independently reran the actual-main-scene test: finite swept hit, endpoint hit, AABB-overlapping circle corner miss and endpoint miss PASS (`root-sp-saw-runtime-final.log`). Scoped staging is accepted; the publication gate is clear.

## Confirmed review findings sent to Luna

1. **Singleplayer late saw instantiation loses simulation history.** The original scene configured its initial state at the current tick while the MP world started from tick zero. In a separate root reproduction, event distance 20,000 and tick 4,501 gave reference x=14,701 versus SP scene x=21,580. SP's support callback also depended on terrain scenes already spawned, rather than the resolved course support map. Required correction: shared resolved support, reconstruction at current tick, and actual scene/world parity with late instantiation.
2. **Absolute 500 px/s activation and static route forecast disagree with variable runner speed.** The original forecast D+525..705 covered the base-speed encounter only. A 750 px/s runner could already pass the initial saw position before its fixed activation tick. Approved correction: authoritative distance-triggered activation using the shared world-event mechanism, one canonical activation per saw, conservative motion-aware route protection at 250/500/750 px/s, and a visible ceiling-to-floor encounter in the normal camera.
3. **MP endpoint/historical collision differs from SP swept collision.** Endpoint contact used a rectangular block hitbox for the circular saw and historical validation read the current saw pose. Required correction: common circle contact and bounded state history at the requested tick, with corner-miss and historical hit/miss regressions. Late activation commits/baselines must reconstruct the same pose; duplicates must not restart motion.
4. **Biome coordinates differ by 180 px between SP and MP.** SP used world x with zero course-origin offset, while MP subtracted manifest.start_x=180. Required correction: one shared course-distance contract and boundary parity at identical world positions.

The corrected diff and targeted evidence were reviewed. Root independently ran the corrected activation/route test: generated seed1 ceiling-origin saw has explicit grounded RunnerMotion routes at 250/500/750 px/s; actual observed floor contacts are inside its planner window. Historical public MP contact, circular corner miss, activation baseline format 2 and duplicate replay pass. First valid samples beyond the activation threshold are accepted.

Root's independent late-SP reproduction compares the actual scene against sequential shared-model simulation across roof-gap fall and floor landing: exact state equality at tick4501, x20677/y430. Dormant replay to one million ticks took6 microseconds. Commit reconstruction is limited to the changed saw; baseline replay retains121 historical ticks. Evidence: `root_saw_correction_check.gd`, `root-saw-correction.log`, `root-activation-route.log` under `.codex-overnight-review`.

Root also ran the real-main-scene SP collision test with finite hit-fraction assertion and an AABB-overlapping circular corner miss: PASS. Baseline codec, release version contract and three-client WebRTC prepare-start integration regressions pass. Logs: `root-sp-saw-runtime.log`, `root-world_baseline_codec_test.log`, `root-release_version_contract_test.log`, `root-prepare_start_integration_test.log`.

SP and MP now pass their respective course origins to the same coordinate helper and shared renderer. Shared hazard models/scenes and the resource-backed biome asset path meet the user's reuse requirement. Route checks are targeted evidence, not exhaustive proof for every seed, surrounding obstacle or item combination.

## Visual review already accepted

Actual NVIDIA/OpenGL captures were inspected in landscape and portrait, plus real SP main-scene and MP course-presentation captures around both biome boundaries. Follow-up corrections removed misleading cave decorations and slope tiles resembling large spikes, preserved classic's dark/turquoise appearance, and made haunted ruins visible above the MP floor. The current placeholder look is accepted; further art polish is outside this release.

The GPU atlas replacement test confirms real texture pixels and clipping at off-grid support boundaries. Biome assets are configured through shared resources. Captures are under `E:/Utveckling/Gravity Run/.codex-overnight-review/`.

## Root database verification

- Fresh isolated local database: `overnight_gen9_root_utf8_20261003`, existing local PostgreSQL on port 55438.
- All 40 migrations' SQL/RLS/function definitions executed in order, including `202610030001_generator9_saw_blade_release.sql`.
- Local Supabase-owned auth/realtime schema shims were used. Hosted pg_cron installation was omitted because this local PostgreSQL distribution lacks the extension; its scheduling branch was inactive. This verifies the migration logic, not GoTrue/PostgREST/Realtime transport or hosted cron.
- RPC smoke test under `authenticated` with synthetic auth claims: create v9/.5 succeeds; v8/.4 creation returns `version_mismatch`; v9 coin registration succeeds and a repeated registration is duplicate-safe. All synthetic test data rolled back.
- Read-only linked Supabase history: all 39 existing migrations match remote; only the new gen9 migration is pending. Existing CLI/credential access works. Nothing applied live.

Evidence: `.codex-overnight-review/root_migration_chain.py`, `root-migration-chain.log`, `root_v9_sql_contract.sql`, `root_saw_repro.gd`, `root-saw-repro.log`.

## Remaining release steps

Proceed with scoped staging/commit. Preserve unrelated capture/pacing hunks and files. Build from an exact clean commit, apply the approved pending live migration, push source to Azure and publish Pages. Verify workflow, public build ID, loader and pack hash. Report any unperformed live multiplayer testing explicitly. Release remains incomplete until those steps are verified.
