# Biome encounters, risk coins and spiked barrel — status

Updated 2026-10-05. **Phase: REVIEW_READY; awaiting root's final review. No commit, live migration, Azure push or Pages publication has been made.**

## Release contract and compatibility

- Published baseline remains generator 11 / manifest 5 / API `2.1.20261003.7`.
- Candidate release is generator 12 / manifest 6 / API `2.1.20261005.8`, visible build `2026.10.05-biome-risk-gen12`.
- Migration candidate `supabase/migrations/202610050001_generator12_biome_risk_barrel.sql` permits exactly the old Gen11/.7 and new Gen12/.8 tuples at create and coin-round registration, and retains achievement receipt processing for those frozen rounds. It changes release gates/functions only; it does not alter wallets, existing rows, policies, or privileges.
- The migration was applied only to disposable local database `overnight_gen12_local_20261005` cloned from local database `overnight_gen9_root_utf8_20261003`. Local authenticated-role tests passed and rolled back their fixtures. **No live migration was attempted.** The local Supabase shim does not prove hosted GoTrue/PostgREST behavior.
- `tools/generator_v11_freeze_test.gd` passes four exact frozen Gen11 manifest/coin fixtures from the clean published baseline. `tools/generator_v8_compatibility_test.gd` passes frozen v6/v7/v8 and v9/v10/v11 format expectations; v12 uses manifest format 6.

## Implemented

- `systems/biome_encounter_mix.gd` defines a reusable deterministic Gen12-only encounter-weight table. Classic uses established weights; Cave favors rocks and saws while keeping spikes, Haunted favors ghosts while retaining other encounters. Earlier generator versions receive multiplier 1. Overall event density remains 1.55; no global density increase was introduced.
- The generator selects biome weights at canonical course distance and prevents profile shifts from crossing biome boundaries. Version gates for older ghosts, saws, and coins use explicit introduction-version constants so Gen11 outputs remain frozen.
- Shared coin planner revision 2 keeps regular lines and adds a minority of optional three-coin risk rows tied to existing static block/spike events. Placement uses the shared surface index, validates support on both lanes throughout the lane-change corridor, computes vertical clearance independently of the selected lane, and rejects rows whose approach/pickup/exit corridor overlaps unmodeled moving hazards (barrels, rocks, saws, ghosts). This deterministic conservative check uses fixed world-distance margins and preserves full/streamed-prefix parity.
- A rare Gen12 spiked variant uses the existing barrel scene and tick model. It destroys only the explicitly breakable paired block, remains lethal and keeps rolling; ordinary barrel rules are retained. `v2_destructible_rules` now states the `spiked_barrel` lethal/consumption policy explicitly. MP uses the existing world ledger for the destroyed block and active barrel state.
- `tools/shared_coin_mode_parity_test.tscn` is a scene-backed regression runner. It fixes the old helper test's missing third generator argument and loads normal autoloads before exercising the shared presentation.
- Review corrections: risk placement no longer rejects every floor row due to a signed floor/ceiling delta. Representative floor and ceiling formations are exercised through the shared world simulation and actual `RunnerMotion`, including coin sweep contacts, a gravity flip, terminal-contact checks against intervening hazards, and a safe bypass route.
- Review corrections: every generated risk row in the bounded cohort is checked against the planner's moving-hazard exclusion and supported lane-change corridor, in addition to support/coin-clearance geometry. The route simulation remains a representative sample rather than a per-row/per-seed reachability proof.
- Review corrections: spiked-barrel contact is not an unknown-kind fallthrough. The shared ledger test checks historical contact, one lethal host commit, idempotent replay/application, baseline reconstruction of destroyed block plus still-live barrel, and ordinary-barrel regression coverage.

## Verification completed

Godot 4.7.2 targeted tests passed:

- `tools/generator_v11_freeze_test.gd`: all four exact Gen11 manifest and coin hashes match.
- `tools/generator_v8_compatibility_test.gd`: frozen older versions and manifest-version policy pass.
- `tools/multiplayer_v2/release_version_contract_test.gd`: source/API, generator constant, visible build ID, migration gates agree.
- `tools/biome_risk_generation_test.gd`: 8 deterministic 100,000 px seeds; 45 risk coins total after moving-hazard/corridor filtering; full/streamed coin prefix parity, risk geometry and actual shared-simulation routes pass. Floor seed `100000014` / `event_00021` and ceiling seed `100000777` / `event_00022` each pass at 250, 500, and 750 px/s with 2× cooldown. Routes collect the three risk coins, switch back, and survive; alternate-lane bypasses avoid the risk row and survive while the shared simulation advances other hazards. Cohort encounter totals: Cave rock+saw 58, Classic rock+saw 40; Haunted ghosts 66, Classic ghosts 0. This is a small targeted sample, not proof that every generated formation or seed is playable.
- `tools/course_manifest_test.gd`, `tools/course_generator_test.gd`, and scene-backed `tools/shared_coin_mode_parity_test.tscn` pass. Coin parity was checked at 45,000 px for seeds 100000014, 100000042, and 100001918; generated/streamed/manifest/presented counts respectively match at 198, 174 and 180.
- `tools/spiked_barrel_shared_simulation_test.tscn`: seed 100000003, `event_00005` spiked barrel breaks `event_00004` block through the shared world ledger and remains active/lethal in shared presentation. It advances six more shared ticks with a multiplier above 1 and asserts decreasing world X; a baseline taken immediately after block impact restores the destroyed block and still-active barrel before lethal contact. Duplicate host commit/replay does not consume twice; a second baseline after lethal consumption restores the barrel as consumed. Gen11 has no spiked variant.
- `tools/singleplayer_spiked_barrel_runtime_test.tscn`: actual main-scene resolver destroys the paired breakable block while retaining the spiked barrel; ordinary barrel behavior remains covered.
- `tools/barrel_motion_test.gd` and local SQL `tools/generator12_release_gate_test.sql` and `tools/multiplayer_achievement_receipt_test.sql` pass.
- GPU capture runner `tools/biome_risk_spiked_barrel_capture.tscn` instantiated Gen12 manifests, `RaceCoursePresentation`, the player scene and a CanvasLayer HUD, then produced ten landscape/portrait captures. The corrected portrait runner is grounded and HUD is visible. Risk coins are from seed `100000014`; spiked barrel from seed `100000003`. Files: `E:/Utveckling/Gravity Run/.codex-overnight-review/biome_{classic,cave,haunted}_{landscape,portrait}.png`, `risk_coins_seed100000014_{landscape,portrait}.png`, and `spiked_barrel_seed100000003_{landscape,portrait}.png`. These are manifest-backed shared-presentation fixtures, not full live `main.tscn` SP/connected MP gameplay captures; portrait view includes unused gray viewport area outside the presentation's world background. They demonstrate the HUD and the selected generated content but do not prove the full in-round UI layout in either mode.
- `tools/biome_risk_main_runtime_capture.tscn` additionally ran the real `main.tscn` with fixed Gen12 seed `100000014`, demo input, and the standard HUD made visible, capturing both orientations to `E:/Utveckling/Gravity Run/.codex-overnight-review/main_runtime_gen12_{landscape,portrait}.png`. This verifies the runtime renderer/HUD path without a live account or user-controlled session. Landscape shows active gameplay content and HUD. Portrait uses the current responsive camera fit and leaves substantial vertical letterbox space; this capture records that layout rather than claiming a portrait redesign. No connected MP gameplay capture was run.

Godot emits environment-only warnings in this workspace about writing `user://logs/godot.log`, shader-cache location, and reading the Windows root certificate store. The tests still exit 0.

## Files and scope

Feature changes are in the Gen12 generator/manifest/ruleset, shared risk-coin planner, shared barrel/world/presentation paths, release metadata, `.005` migration, and focused tools/tests listed above. `main.gd` also contains pre-existing capture instrumentation; preserve it and stage only the Gen12 gameplay hunk if later approved. Existing dirty capture, pacing, menu and planning files remain unrelated and must stay out of this task's commit.

## Remaining before release

Root should inspect the implementation/status and migration diff. If accepted, selectively stage only this task's changes (including the gameplay-only `main.gd` hunk), then use the established clean-commit export, migration approval, Azure source push, Pages `docs/game` publication, and verify workflow/live PCK hash. No live action is authorized in this REVIEW_READY phase.
