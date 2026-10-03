# Overnight Ghost, SFX and Multiplayer Achievements — Status

Updated 2026-10-04. **RELEASED — root approved the implementation; scoped source commit, reviewed migrations, and Pages publication are complete.**

## Contract and preservation

- Published baseline: generator 10, manifest 5, API `2.1.20261003.6`; current implementation targets generator 11, manifest 5, API `2.1.20261003.7`.
- Manifest serialization remains unchanged; gen10 and earlier generation rules are explicitly preserved. Frozen gen9 manifest fixtures still match.
- Migrations: `.003` adds the gen11 gate and authenticated per-round achievement receipts; `.004` makes duplicate start retries succeed after lobby-generation changes, atomically updates shared account distance/best-distance without wallet changes, and returns confirmed progress. Both were applied only to local PostgreSQL test database `overnight_gen9_root_utf8_20261003`; neither has been applied to the linked/live backend.
- The shared worktree contains unrelated prior edits. In particular, do not sweep unrelated `main.gd`, menu, render-capture, or frame-pacing changes into any later scoped commit.

## Implemented

- Added a deterministic gen11 ghost hazard with shared model, scene, event/profile generation, world-simulation history/baseline support, shared SP/MP presentation and contact handling. It is excluded from gen10 and earlier rules.
- Added interchangeable SFX assets/controller and separate settings, with round/entity deduplication and shared event wiring. Pause and mute stop/prevent playback; music settings and rewards remain separate.
- Added account-scoped multiplayer achievement begin/terminal receipts and a durable retry queue. The match only starts a receipt on a real round-start callback, and only submits the local participant's terminal result. Provisional coin/wallet totals are excluded. Coin achievement totals change only by the new delta actually credited by wallet settlement.
- The receipt queue now skips unfinished started rounds, explicitly abandons a started round on abort/leave, rotates transient failures and discards permanent failures so stale rows do not starve rematches. Late callbacks are scoped to their immutable account/round/slot row and no longer block another account's dispatch.
- Retry classification no longer treats every HTTP 4xx as permanent: transient/auth/rate-limit/timeout failures retain their payload with persisted exponential backoff, and an expired current session requests auth refresh. Synchronous provider failures are deferred to avoid recursive dispatch; dispatch can skip a backed-off row and serve a later healthy round.
- MP metric receipts apply the server's shared `total_distance_m`/`best_distance_m` to the matching authenticated account. No wallet or SP seed-leaderboard values are derived from those metrics.
- Added a localized result section using the existing achievement icon/title definitions. It buffers confirmed unlocks that arrive after `finish_run`, shows them only for the matching terminal round and local slot, and deduplicates receipt retries.
- SP saw and coin event-resolution calls pass the active generator version. The real SP ghost path resolves future terrain support through the manifest resolver instead of querying only already-instantiated terrain.
- Ghost presentation rejects stale ticks/activation changes, and the warning is visible through a short shared SP/MP centered pulse while collision continues to follow authoritative ticks.
- Coin-collection SFX now checks the current presentation camera bounds. Remote/offscreen coin awards stay silent; local visible prediction and confirmation remain deduplicated.
- Single-player gameplay SFX now use a shared guarded route that is disabled in the menu's `demo_mode`. The guard does not change MusicController state, and the real-main-scene regression verifies demo activity cannot play gameplay SFX or reset the SFX/music round identity.
- Added local Godot and SQL regressions for ghost generation, shared presentation, sound pool/settings, account queue/retries, compatibility gates and receipts.

## Verification completed

- Godot editor scan completed without project-script parse errors. The sandbox cannot write the normal Godot editor cache or `user://` log, and prints those environment errors; the targeted scene and script runs below load successfully.
- `ghost_hazard_shared_test.gd`: PASS, 120 seeded courses, deterministic output, both lanes, shared simulation/contact and route checks at 250/500/750 speed.
- `ghost_presentation_shared_test.tscn`: PASS. The actual shared hazard scene has matching SP/MP collision at the same tick; warning/expired phases are harmless; out-of-order duplicate warning snapshots play one round-scoped warning sound.
- `singleplayer_ghost_runtime_test.gd`: PASS against actual `main.tscn`, GR11-100000000. The scene resolves a generated ghost and saw with the active generator version, the ghost's resolved support matches the shared manifest, and shared coin planning executes.
- Actual GPU captures from the shared ghost scene are available for review at `E:/Utveckling/Gravity Run/.codex-overnight-review/ghost-hazard-landscape.png` and `E:/Utveckling/Gravity Run/.codex-overnight-review/ghost-hazard-portrait.png`. Captures show warning, dangerous, and fading presentation against the same upper/lower course supports.
- The new center HUD warning is exercised in both the real SP `main.tscn` runtime path and MP `RaceCoursePresentation` signal path. Refreshed actual-renderer captures are available at the landscape and portrait paths above; the warning pulse is centered separately from the course hazards.
- `sfx_shared_pool_test.tscn`: PASS. Real coin-scene presentation signal starts one SFX across prediction/confirmation without firing a reward; reset, pause, mute, volume persistence and music-bus isolation checks pass.
- `multiplayer_achievement_queue_test.tscn`: PASS. An unfinished started round does not block a rematch; account switching/late ACK, permanent HTTP 400 cleanup, progress application, signed-in gating and SP-wallet queue separation pass.
- `multiplayer_achievement_retry_backoff_test.tscn`: PASS. HTTP 401 and 429 retain receipt payloads with backoff, a newer round gets a dispatch turn, and a synchronously emitted `busy` result does not recurse; maximum synchronous dispatch depth was 1. The test suppresses an actual auth refresh request while injecting 401, so refresh transport itself is not claimed as tested.
- `mp_achievement_result_section_test.tscn`: PASS. A real AccountProgress terminal-receipt callback after `AchievementService.finish_run()` displays a confirmed unlock once in the result section; stale rounds/slots are ignored and rematch clears the section.
- The achievement queue tests use test-only ignored `.godot` persistence files; they do not read or remove the real user achievement queue.
- `generator_v8_compatibility_test.gd` and `generator_v9_smoke_test.gd`: PASS. Explicit old-version behavior remains frozen; gen9 hashes match published fixtures.
- Multiplayer coin commit/contact integration tests, multiplayer contract test, release version contract test and shared music layout test: PASS.
- Local PostgreSQL `.003` + `.004` chain and `multiplayer_achievement_receipt_test.sql`: PASS under authenticated role with synthetic auth identities. Tests cover version gates, registered account/slot binding, RLS, duplicate start after phase/generation change, start/terminal idempotence, conflicting retries, progress totals, and wallet plus achievement coin delta exactly once. Test transaction rolled back.

## Limits and remaining review

- PostgreSQL uses local Supabase auth/realtime shims and synthetic identities. This verifies SQL authorization semantics and idempotence, not a live GoTrue/PostgREST authenticated multiplayer session.
- No live migration or live multiplayer session has been attempted. Root must review the implementation and migration before any deployment step.
- Achievement distance/hazard/flip metrics are based on the participant's terminal simulation report; this feature does not add server-authoritative anti-cheat validation.
- SFX wiring and controls are covered by local integration tests, including audible/offscreen coin presentation gating and menu-demo suppression, but there has been no user listening/art review in a browser.
- The headless SP test invokes the actual main-scene resolver/spawn methods and confirms the resolved shared support, but does not simulate a full-length run until a generated ghost warning and collision. The standalone shared-route test covers real RunnerMotion crossings at 250/500/750 px/s with and without a lane switch.
- Godot on this machine reports inability to write `user://logs/godot.log` and failure to read the Windows root certificate store. These environment messages persist; targeted tests above still complete with their stated pass results.

## Release evidence

- Root approved the implementation and the two migrations before release. Source commit `cb14b78` (`Add shared ghost, SFX, and multiplayer achievements`) was pushed to Azure `codex/current-prototype`.
- The Web export was built from the clean archive of exact commit `cb14b78`, at `E:/Utveckling/Gravity Run/.codex-overnight-review/clean-cb14b78`. Godot 4.7.2 editor import completed; `singleplayer_ghost_runtime_test.gd` then passed against that clean archive (`seed=100000000`, failures=0).
- Before live deployment, linked migration history matched through `202610030002`; dry run listed only `.003` and `.004`. Both reviewed migrations were applied. A subsequent linked migration list confirmed local and remote history match through `202610030004`.
- GitHub Pages commit `5119043` (`Publish gen11 ghost, audio, and achievements build`) was pushed to `https://github.com/hjelmdev/gravity-run.git`, branch `main`. The existing root wrapper and active `docs/game` bundle were updated; historic versioned packs and redirect paths were preserved.
- Public build identifier: `shared-ghost-sfx-achievements-gen11-cb14b78-20261004`. Public game pack: 3,079,996 bytes, SHA256 `CF4ACA0608ED67D7E79C13F15D15C0E905CD98D8647722A9E5DD6F3F93233F9E`; this exactly matches the clean-archive export. The root loader and game index both returned HTTP 200 with the new build ID and pack reference.
- The Pages repository has no checked-in GitHub Actions workflow, and the GitHub Pages “latest build” API returned 404. Direct root, loader, and pack checks confirm the branch-published site serves the new bundle. A desktop browser screenshot/console review was unavailable in this thread; root was asked to perform the final visual check if its browser session is available.
- Live authenticated multiplayer achievement play was not performed. SQL was validated with local PostgreSQL/Supabase shims and synthetic identities; SFX were integration-tested locally but not artistically reviewed by the user in a browser. The Godot sandbox also reports denied normal user-profile/editor-cache writes; the SFX persistence test passed when run with the approved host profile. These do not indicate failures in the targeted feature tests.
- Unrelated dirty `main.gd` capture instrumentation, `ui/main_menu.gd` capture routing, frame-pacing files, and other pre-existing working-tree changes were excluded from the source commit.
