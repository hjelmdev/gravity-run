# Root review — ghost, SFX, MP achievements

2026-10-03, review of Luna's first REVIEW_READY delivery. Decision: **CHANGES REQUIRED; not approved for live migration or publication.** Luna is running again to address the findings below. Preserve unrelated working-tree changes.

## Required corrections sent to Luna

1. MP pending queue dispatches only queue[0]. A started/incomplete aborted round can permanently block all future receipts. Select dispatchable work, define abandon/abort behavior, prevent permanent failures starving later rounds, and test unfinished first round followed by a completed rematch.
2. SQL start-receipt retry checks current lobby generation/phase before recognizing an existing receipt. Lost start ACK followed by return/rematch prevents idempotent recovery. Verify existing bound receipt first; keep initial-start validation and test lost ACK plus changed generation.
3. MP metrics update achievement distance only, not shared player_progress distance/best. AccountProgress and AchievementService's progress_changed callback can then restore inconsistent SP-only totals. Apply account distance exactly once without wallet/SP-seed-leaderboard awards; return/apply matching progress fields and test retry/account switching.
4. MP coin audio binds play_event directly with audible=true. Offscreen remote pickups therefore play local audio. Gate the actual coin presentation event using current camera/coin location; preserve prediction+confirmation dedup and rejection-reset behavior.
5. Main.gd has two dynamic _resolve_events calls with the obsolete two-argument signature after the builder made generator_version required. Fix both with active generation version and verify actual main.tscn execution with coin/saw/ghost, including historical challenges. Ghost early spawning also queries supports before future terrain is spawned; derive support geometry from the same resolver used by MP and test slope/step placement.
6. Ghost scene accepts older ticks and changed activation ticks, allowing expired/danger phases to revert on stale snapshots. Make entity/round state monotonic with an explicit configure reset; assert late snapshots do not revive collision or presentation. Validate a visible warning in real approach at 250/500/750: lead2200 and warning120 mean warning can finish offscreen. Existing 299-tick route fixture never reaches x2500 at 250px/s; test actual passage and no-flip collision risk where applicable.
7. MP terminal achievements arrive asynchronously after finish_run, but result UI has no achievement signal/component hook; neither result view nor run toast displays those unlocks. Reuse shared achievement presentation, scope late response to correct round and test scene/signal behavior after terminal response, once only.

## Reviewed evidence

- Read actual account queue, achievement service, MP match/service wiring, shared presentation, ghost model/scene, generator/profile/resolver, SFX controller, provider and new migration.
- Viewed actual GPU landscape ghost capture: placeholder silhouette and phase contrast are usable. This fixture is static and does not verify approach warning visibility or actual main integration.
- Luna reports scoped Godot and local authenticated-role SQL tests PASS. These are useful but missed the dynamic-call and lifecycle issues above; additional behavior regressions are required.
- No live backend or publication action was performed by root.

## Next root turn

Read Luna's correction report and updated STATUS once. Review concrete changes for all seven findings, rerun only appropriate critical checks, inspect actual SP/MP integration/captures. Only approve release when these are resolved and source staging preserves previous dirty hunks. Then have Luna follow the plan's Azure, clean-archive, migration, Pages workflow and public hash/browser checks. Pause the associated heartbeat only once delivery is fully verified and the user notified.

## Second review checkpoint, 2026-10-03 21:43 UTC heartbeat

Luna completed corrections for findings 1–7 and authored local `.004_mp_achievement_retry_progress.sql`. Root read the queue/RPC, monotonic ghost state and actual SP resolver regression and independently ran:

- `singleplayer_ghost_runtime_test.gd`: PASS seed100000000, actual main scene, ghost future supports, saw resolver and coin plan.
- `mp_achievement_result_section_test.tscn`: PASS actual late AccountProgress callback to results.
- `ghost_presentation_shared_test.tscn`: PASS shared scene/pulse/monotonic state.

These runs exit0 with only previously documented certificate/user-log and fixture teardown messages. No parse or gameplay assertion errors.

Release still held for narrow additional corrections sent to Luna:

- Retry queue treats all HTTP4 as permanent, including401/429/408. Preserve valid receipts across recoverable auth/rate-limit failures.
- Transient callback starts backoff timer but also immediately dispatches the same row; synchronous provider-busy errors can recurse. Bound/defer retries per entry and test immediate failure, later rematch progress and timer eligibility.
- Main-menu demo uses gameplay main scene, whose SFX handlers need demo-mode suppression; keep actual music unchanged.
- Refresh center-warning GPU capture with real renderer, not dummy headless renderer, if feasible.

Root has not approved live migration, commit or Pages yet. Luna is running on these corrections. After completion, inspect only these changes and any clean-archive issues rather than repeat the entire broad test suite without cause.

## Final implementation review, 2026-10-03 21:58 UTC heartbeat

**APPROVED for selective source commit and the plan's release procedure.** The historical decision above describes the initial review, not the current release gate.

Root inspected the corrected per-entry persistent backoff/deferred dispatch, semantic permanent-error classification, demo audio guards and refreshed actual-renderer portrait capture. Root independently ran `multiplayer_achievement_retry_backoff_test.tscn`: exit0, failures0, starts4, records1, maximum synchronous depth1. Together with the preceding root SP/runtime, ghost scene and late-result tests, the required corrections are resolved.

Both new migrations `.003` and `.004` were read; local authenticated-role chain/receipt tests are reported PASS. Live application remains part of release and must follow tool approval. This approval does not bypass that review or assert a live signed-in MP test has occurred.

Luna should now selectively stage/commit only feature changes, push Azure, prepare the exact clean archive, run actual SP start/import checks there, build Web, apply the reviewed migration chain, publish existing Pages root and verify workflow/loader/public PCK hash/browser load. Release is not complete until that evidence is recorded and root confirms it. Preserve unrelated main/capture/menu/pacing changes throughout.

## Final release verification, 2026-10-04

**FINAL RELEASE CHECK: PASS.** The preceding sections record the review history; the initial rejection and intermediate approval hold are resolved.

- Source feature commit `cb14b78` was pushed to Azure `codex/current-prototype`; the final report follow-up is tracked separately.
- Live migrations `202610030003` and `202610030004` were applied. Linked migration history matches local through `.004`.
- Pages commit `511904366d2cd9ed47061fb6f29aa11689e267e1` published the existing root wrapper and `docs/game` bundle. GitHub Pages workflow [37157743407](https://github.com/hjelmdev/gravity-run/actions/runs/37157743407) completed successfully.
- Root opened the live page in a browser and verified the wrapper iframe used build `shared-ghost-sfx-achievements-gen11-cb14b78-20261004`, the main menu and demo loaded, and the page had no browser development errors or warnings.
- Public PCK size was 3,079,996 bytes; SHA256 `CF4ACA0608ED67D7E79C13F15D15C0E905CD98D8647722A9E5DD6F3F93233F9E`, exactly matching the clean-archive export.
- Remaining verification limits: no real signed-in multiplayer achievements match was played, and no user listening/artistic review of the SFX was performed. Local SQL tests used synthetic identities/Supabase shims; browser verification confirms the published build loads, not those user-facing sessions.
