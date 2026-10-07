# Gen20 narrow-corridor spacing, barrel relevance, and coin trace

Status: REVIEW_READY. No commit, migration apply, or publication. Preserve Gen17–19 outputs and all unrelated dirty work.

## Scope and candidate

Gen20 is the only generated course version changed. The current candidate narrows event spacing only in supported two-lane corridors, moves ordinary barrel chains beyond their paired base obstacle, restores the deterministic spiked-role probability to 0.25, and batches Gen20 SP coin replanning at 250px. Coin resolution sees the future hazard/support range needed by the full-course planner; the earlier versions keep their old lookahead and refresh behavior. Barrel destruction, collision, wallet settlement, and coin awards are unchanged.

## Matched cohort (20 seeds, 45km each)

Latest matched Gen19→Gen20 run: accepted hazards 928→1021 (+10.0%); narrow supported center density 0.9577→1.1266 per 1000px (+17.6%); largest accepted-center gap 8431.4→7312.1px (−13.3%); planned coins 3173→3404 (+7.3%). Common narrow-terrain intersection: Gen19 378.4km with 345 centers, Gen20 408 centers. Terrain profiles are not byte-identical across generator versions, so own-terrain and intersection-normalized figures are both retained. These are generated/accepted spatial measurements, not proof every encounter is reachable or collected.

## Barrel comparison

Across eight matched 45km seeds at 475/500/525px/s, ordinary floor-path meetings increased from 15/50/38 (Gen19) to 54/82/43 (Gen20). The small subset had 14 versus 3 spiked members; the 20-seed cohort had 31 versus 29, so the eight-seed spike difference is sampling variance, not an intended reduction. At 525px/s ordinary pre-meet destruction remained common (40/95 vs 28/68); the change improves absolute meetings but does not eliminate early destruction. Shared collision/destruction behavior is unchanged. Floor-path tests remain counterfactual, supplemented by actual SP generated-barrel spawn coverage.

## Coin contact investigation and opt-in trace

A user smoothness log does not record coin-node state or awards, so the reported missed pickup is not yet confirmed. Root's bounded actual-main geometric reconstruction for Gen19 seed `1580534762` found several real swept-contact opportunities (including IDs/positions around x5014–5091 at y114 and x9140–9691 at y426), but did not observe node visibility, collection, or wallet award. This is evidence of geometric opportunity only.

An opt-in bounded coin trace is included in the existing single-player smoothness diagnostics. When diagnostics are off, no trace dictionaries/rectangles are built. When enabled, the report includes seed/generator/build, capped spawn, near-sweep, swept-contact, collect, and offscreen-uncollected events, with runner/coin rectangles, contact and lethal fractions, before/after run coin counts, a 512-record cap, and dropped-record count. Mid-run enable records active coins with canonical IDs. It is diagnostic instrumentation only; it does not change pickup decisions.

## Coin-replan cost and cadence

The Gen20 refresh interval is 250 world pixels. On the same seed `100000014`, actual-main adapter measurements through the first 10km were: Gen19 101 refreshes, 49.1ms total, 2.93ms maximum; Gen20 41 refreshes, 43.6ms total, 4.80ms maximum. Through 45km: Gen19 451 refreshes, 1360ms total, 15.77ms maximum; Gen20 181 refreshes, 828.2ms total, 19.34ms maximum. Thus total measured work is lower at both distances, while the worst individual Gen20 refresh is higher; this does not establish or fix the reported ~250ms browser callback stalls. A 250px cadence trial reduced the 45km maximum versus the previous 500px candidate (~20.35ms) and retained parity.

## Expanded coin parity and viewport evidence

The 250px cadence parity test passed for 12 matched seeds with no stream/manifest differences: `100000001`, `100000003`, `100000006`, `100000014`, `100000019`, `100000030`, `100000042`, `100000057`, `100000100`, `100000107`, `1580534762`, and `918273645`. The last two include a published-generation user seed and a challenge-style seed.

Bounded GPU capture fixture: `tools/gen20_gameplay_view_capture.tscn` / `.gd`; final MP-only rerun log `gen20-gameplay-capture-mp-final.stdout.log` (exit 0, zero fixture failures). The actual `main.tscn` SP run captured at 3,750px using Gen20 seed `100000014`, with HUD visible, three ordinary barrel nodes and a spike row in view: `.codex-gen20-gameplay-captures/gen20-sp-seed-100000014.png`. This is a real SP gameplay scene, but the selected location is not proven to be a <=300px narrow corridor.

The refreshed MP captures are offline match-scene fixtures, not connected multiplayer. They now configure one local roster entry, a grounded running pose sampled from the actual shared world support, and the round clock/world tick at the same simulation time. `gen20-mp-offline-match-narrow-seed-100000006.png` shows the runner grounded on the generated slope with three ordinary rolling barrels entering view; capture tick 2378, active barrel at screen x≈839, HUD visible. `gen20-mp-offline-match-barrel-seed-100000014.png` shows two active ordinary barrels at screen x≈846, HUD visible. This verifies the real match scene/presentation path and shared barrel state in an offline fixture, but not a network-connected match or independently advancing peer clients. The test starts the fixture in running presentation state; it does not claim to exercise lobby prepare/countdown barriers.

## Relevant evidence

- `tools/gen20_spacing_cohort_test.gd`: latest matched cohort passed; log `gen20_spacing_cohort_role25.stdout.log`.
- `tools/gen20_barrel_reach_comparison_test.gd`: 475/500/525 comparison passed; logs `gen20_barrel_reach_role25.stdout.log` and `gen20_barrel_reach_role25.stderr.log`.
- `tools/gen20_full_manifest_pursuit_route_test.gd`: actual RunnerMotion, full-manifest routes passed for seeds `100000030` and `100000019` at 250/500/750px/s; logs `gen20_fullmanifest_role25.stdout.log` and `gen20_fullmanifest_role25.stderr.log`.
- `tools/gen20_narrow_corridor_classifier_test.gd`: canonical `CourseSurfaceIndex` comparison passed, zero mismatches over 450 samples per seed for `100000006`, `100000014`, `100000019`, `100000030`.
- `tools/gen20_coin_stream_parity_test.gd` and `tools/gen20_coin_main_integration_test.tscn`: four-seed SP adapter/MP-plan parity passed (`100000006`, `100000014`, `100000019`, `100000030`), 141/141, 178/178, 175/175, 112/112 coins.
- Latest cadence rerun: `tools/gen20_coin_stream_parity_test.gd` and `tools/gen20_coin_main_integration_test.tscn` passed after switching to 250px; the latter also exercised actual-main Gen19 seed `1580534762` trace reporting and a real coin collect signal/count.
- Expanded 12-seed parity rerun passed with no mismatches; output `gen20-coin-parity-12seed.stdout.log`.
- Bounded NVIDIA/OpenGL viewport capture completed with exit 0 and saved the actual SP main-scene image plus the grounded running-state offline MP match-scene images listed above. The MP fixture has no network peers and does not verify prepare/countdown or a live network match.
- `tools/gen20_coin_replan_cost_test.tscn`: same-seed first-10km and 45km refresh count/total/max cost comparison above; log `gen20-coin-replan-cost250.stdout.log`.
- `tools/multiplayer_v2/release_version_contract_test.gd`: passed current `.16`/Gen20 and migration gate contract; log `gen20-release-contract-final.stdout.log`.
- `tools/gen20_singleplayer_barrel_spawn_test.tscn`: actual main scene spawns generated seed `100000006` event `event_00009` once at expected position.
- Gen17 and Gen18 freeze tests passed after final candidate; Gen19 activation-contract assertion was corrected to compare fractional render pose to the model at the same render tick, then passed. Gen19 game behavior was not changed.

## Version/migration draft and limits

Source version draft is generator 20 / game API `.16`; project build label is `2026.10.07-gen20-barrel-gap-rhythm`; manifest stays format 13 and baseline stays format 4. Draft migration: `supabase/migrations/202610070002_generator20_narrow_gaps_barrels.sql`, copied from `.001` with only current game/generator tuples and achievement receipt allowlist updated. It has not been applied. Root review of migration and contract test is pending. No live database or web changes have been made.

Known limitations: no full authenticated multiplayer/browser test. The MP images are offline match-scene presentation fixtures with a grounded runner and live shared barrels; they do not verify lobby prepare/countdown or a network-connected round. Route and barrel metrics are bounded generated cohorts and model-based floor contacts. The Gen19 coin report still lacks direct award/node-state data; the new opt-in trace provides evidence collection for a future reproduction, but does not prove the reported pickup issue is fixed. Total replan CPU cost is below Gen19 in the measured adapter, but worst single refresh rose from 15.77ms to 19.34ms at 45km. No claim is made that the missed coin, in-run lag, or all long empty stretches are fixed.
