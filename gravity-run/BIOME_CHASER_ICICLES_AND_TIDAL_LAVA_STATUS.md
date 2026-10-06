# Biome meetings: chaser ghost, icicles and tidal lava — status

Status: REVIEW_READY — requested Gen17 correctness regressions, actual SP captures for pool/chaser, and mobile seed-field integration/tests are complete. Awaiting root review. No commit, live migration or publication has been performed.

## Baseline and compatibility

- Baseline HEAD: `d3f9a4b4fd69fa9804d8fcc6b4dfa5a090dbb38f`, branch `codex/current-prototype`; published API `.12`, Gen16, manifest 9.
- Candidate: API `2.1.20261006.13`, Gen17, manifest 10. The draft migration is `supabase/migrations/202610060002_generator17_biome_meetings.sql` and only adjusts release gates/receipt generator allowlists. It was applied to a disposable clone of the prior local Gen16 test database, `gen17_candidate_test`; no live database was touched.
- Four frozen 45,000 px Gen16 manifest/event/coin hashes (seeds 100000014, 100000042, 100000918, 100000777) pass unchanged via `tools/generator_v16_freeze_test.gd`.
- Existing dirty audio, death, touch, cave, capture and unrelated gameplay hunks are being preserved. No `AGENTS.md` was found.

## Implemented contract

- Haunted chaser: `kind=ghost`, `ghost_variant=1`; shared ghost activation ledger and simulation tick drive warning, chase and collision. The path is event-derived behind the runner and leaves supported ceiling escape; no camera, wall-clock, per-peer targeting or host-local choice.
- Cave icicle: `kind=rock`, `rock_variant=1`; shared rock activation drives warning, fall, temporary lodged state and expiry. It only lodges on resolved floor support; falling through a gap expires permanently. Collision/render pose use the same model.
- Lava tidal pool: `kind=lava_crack`, `lava_variant=1`; shared lava event/tick drives a bounded expanding/contracting pool. Contact bounds follow visible geometry; floor support remains present.
- Gen17 variants are filtered against resolved terrain and risk-coin exclusion before manifest publication. No wallet/account path or new ledger fields are introduced.

## Verification checkpoint

- `tools/biome_gen17_shared_encounters_test.tscn`: PASS after review fixes, exit 0, failures 0. It exercises the legacy ghost boundary, Gen17 post-resolve filter parity for SP/MP and coin planning, supported/gap icicle expiry sweep, shared pose/contact rules, activation/baseline behavior, and full-manifest `RunnerMotion` passages at 250/500/750 px/s with the selected warning/fase offsets.
- `tools/biome_gen17_singleplayer_spawn_test.tscn`: PASS against actual `main.tscn`; generated Gen17 chaser, icicle and tidal-pool adapters retain shared metadata/support (`gen17-sp-main-filter-final.stdout.log`).
- `tools/generator_v16_freeze_test.gd`: PASS, exit 0; all four frozen Gen16 manifest/event/coin hashes exact.
- `tools/multiplayer_v2/release_version_contract_test.gd`: PASS, exit 0; API `.13`, Gen17/manifest10 and draft migration gates agree. `tools/localization_test.gd`: PASS with the added Swedish mobile seed labels.
- `tools/gen17_release_gate_test.sql`: PASS against the disposable local PostgreSQL clone under `SET ROLE authenticated` and a synthetic JWT subject, wrapped in `ROLLBACK`; `gen17-release-gate-final.log`. It verifies mixed `.12`/Gen17 rejection, `.13`/Gen17 and `.12`/Gen16 acceptance, duplicate-safe Gen17 coin-round registration, and idempotent achievement start receipt. Supabase auth/realtime shims mean this does not prove hosted GoTrue/PostgREST behavior. No live SQL was changed.
- Mobile seed entry: `tools/mobile_seed_entry_integration_test.tscn` PASS, exit 0. The test uses actual Game Hub and MP lobby scene controls in simulated 960×540 landscape and 390×844 portrait SubViewports; it simulates the existing `MobileTextEntry.entry_submitted` result and checks launcher viewport visibility, hidden native fields, GR16 replay parsing/current numeric seed selection, active-challenge lock, MP seed integer range and room-code length. `tools/game_hub_compact_layout_test.tscn` and `tools/singleplayer_seed_replay_integration_test.tscn` also PASS after updating the stale Gen15 assertion to the current generator constant. The SubViewport size is a layout fixture, not a real Safari/Chrome keyboard or inset test.
- Reproducible short seeds: Haunted chaser `100000019` at course distance 2600 px; cave icicle `100000002` at 3977 px; tidal pool `100000057` at 1400 px. Actual normal SP captures use pool seed `100000057` at 1767 px and chaser seed `100000019` at 2958 px.
- The actual gameplay capture runner completed with `failures=0` and wrote two 960×540 images. Selected seed `100000016` for a third main-scene icicle image dies earlier on a separate encounter (at 1358 px), before the icicle at 3196 px; that image was excluded rather than presented as an icicle gameplay view. Icicle phase/burial evidence remains in the tick-sampled shared scene captures.
- Godot checks were run serially with bounded runs and exited before the next test. The sandbox logs expected local `user://logs`/certificate-store warnings; test assertions and exit codes passed. Only the user's editor PID 53204 remained open at the last process check.

## GPU and cohort evidence

- Production hazard scenes were rendered by Godot 4.7.2 on NVIDIA OpenGL Compatibility at 960×540 and 540×960. Eight captured fixtures show chaser warning/danger, icicle warning/falling/lodged, and tidal pool low/growing/high/retracting phases: `.codex-gen17-review/gen17-biome-{chaser,icicles,tidal-pool,tidal-pool-retracting}-{landscape,portrait}.png`.
- The chaser/icicle/pool phase panels are tick-sampled shared-scene fixtures with drawn support surfaces. In addition, actual running `main.tscn` landscape captures show the active tidal-pool and chaser variants with the regular HUD at `.codex-gen17-review/actual-main/gen17-sp-tidal-pool-landscape.png` and `gen17-sp-haunted-chaser-landscape.png`. The icicle did not receive an actual death-free main-scene capture for the reason above. No connected online MP session or mobile browser was exercised.
- Bounded 40-seed, 45,000 px accepted-manifest comparison (`tools/gen17_generation_cohort_test.gd`, `gen17-cohort-final.stdout.log`): Gen16 accepted 1,953 hazard events (1.085 per 1,000 px), 7,051 coins (3.917 per 1,000 px), maximum 8,361.5 px between encounter centers. Gen17 accepted 1,827 hazards (1.015 per 1,000 px), including 78 new variants (19 chasers, 26 icicles, 33 pools), 6,451 coins (3.584 per 1,000 px), maximum 7,054.2 px. All 80 manifests built. Total accepted counts fell 6.5% for hazards and 8.5% for coins in this sample after adding profiles and filters; this is not an overall density increase. These are event-center distribution proxies, not player-visible reaction-time or solvability guarantees.

## Review limits and environment

- Route tests cover selected generated manifests, actual support and RunnerMotion at 250/500/750 px/s; they are not a proof of all-seed solvability. V2 world/presentation tests are local/offline, not a connected peer session.
- Mobile input reuses the `MobileTextEntry` parent-page bridge already used by nickname, room code, account and challenge fields. The inventory found editable SP Game Hub seed and MP create-room seed had still been plain mobile `LineEdit`s; both now use the shared launcher. Main-menu account/challenge fields, MP nickname/room code, and run-end nickname already used the bridge. Read-only challenge-code/link fields and sliders are unchanged. The test simulates the bridge callback and confirms seed/parser/range handling, but no actual device/keyboard inset verification is available.
- The local PostgreSQL test server on loopback port 55438 was started for this task with the existing workspace-local `pg_ctl`; PID 61636 was the `postgres.exe` process in the workspace-local test cluster, not the user's editor. At final check, `pg_ctl status` reported no server running, and I did not send a stop/kill command. Tests used the existing cluster owner and a disposable database clone; no live database was changed.
- The local SQL run relies on Supabase auth/realtime shims and synthetic JWT claims. It verifies migration SQL and database-side role/receipt behavior, not live Supabase authentication, network transport or hosted concurrency.
- Godot tests were bounded and run serially. All task-owned Godot test processes exited; the user's editor was not terminated.

## Latest checkpoint (2026-10-06)

- The three requested review corrections are in the working tree and retested: Gen16 stationary ghosts retain published collision boundaries; only Gen17 chaser variant uses the new swept path; SP resolvers and coin filtering share the MP post-resolution Gen17 terrain filter; and Gen17 icicle sweep ends at its supported/gap expiration without interpolating toward an empty origin rectangle.
- Actual main capture runner reached the pool and chaser encounters with live variant nodes and HUD visible, `failures=0`. The first chosen icicle seed died before its target on a different event, so only phase-fixture evidence is claimed for that meeting.
- The new mobile text-input hookup routes SP and MP seed controls through the existing parent-page `MobileTextEntry` bridge; desktop text fields, SP seed parser, MP numeric validation, nickname and room-code paths remain intact. The simulated bridge/scene test passes. Physical keyboard movement, paste and cancel behavior still need real mobile-browser confirmation.
- No implementation commit, live migration, or publication has occurred. Draft `.002` remains unchanged; the mobile field work does not require a new API, generator or database change.
