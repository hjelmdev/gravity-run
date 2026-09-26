# Achievement system — implementation and extension guide

## Goals and product decisions

- Achievements belong to an authenticated Supabase account, keyed by `auth.uid()`—never by nickname.
- Guests do not earn or persist achievement progress. There is no guest-to-account achievement import.
- Definitions, supported criteria, tiers, titles, descriptions, and visibility live in the normalized Supabase catalog; the client fetches that catalog rather than keeping a second hardcoded list.
- Separate achievement conditions from rewards. Unlocking an achievement may grant a future item/entitlement, but the achievement system must not depend on inventory existing yet.
- The main menu gets an Achievements entry for signed-in players. The screen should show unlocked tiers and progress toward visible achievements.

## Player-facing visibility recommendation

Use two visibility modes:

1. **Visible**: show locked and unlocked achievements, including progress and next tier. These give players useful goals.
2. **Secret**: hide title, description, and criteria until unlocked; show only a generic “Secret achievement” placeholder (or hide the row entirely).

This allows both discoverable progression and surprises without forcing every future achievement into one policy. Start with visible achievements; add secret entries only when there is a concrete reason. Keep the UI copy localized.

## Architecture

### 1. Definitions/catalog (Supabase source of truth, stable IDs)

`achievement_definitions` has one row per tier and stores stable `achievement_id`, `tier`, `metric`, `threshold`, optional `scope_key`, title/description localization keys, and visibility. `AchievementService` fetches these rows using `get_my_achievements()` and uses the same data for progress, the menu, and live milestone toasts. There is no parallel GDScript catalog. Never use display text as an identifier.

The initial evaluator registry supports:

- `total_distance_m`, `best_run_distance_m`, `total_coins_earned`, and `total_gravity_flips`: threshold metrics.
- `distinct_hazards_seen`: threshold over the count of hazard types encountered.
- `hazard_encounters`: per-hazard encounter-run count, selected by `scope_key`.

Thresholds and tiers are data, not hardcoded branches. Adding a tier or another achievement using one of these metrics is a catalog insert plus localized text; it does not require a new evaluator. A genuinely new criterion needs one evaluator in the SQL RPC and client progress projection, then it can be reused by catalog rows. Use migrations for catalog edits so they are reviewable and repeatable.

For example, another lifetime coin tier can be added with a migration row like:

```sql
insert into public.achievement_definitions
	(achievement_id, tier, metric, threshold, scope_key, title_key, description_key, visibility)
values
	('coins_earned', 4, 'total_coins_earned', 2500, '', 'Coin saver IV', 'Collect 2,500 coins in total.', 'visible');
```

Then add the new title and description keys to the locale catalog. Existing UI, progress bars, milestone checks, and server unlock logic pick up the row dynamically.

### 2. Account persistence (Supabase is authoritative)

Current normalized tables:

- `achievement_definitions`: one catalog row per achievement tier.
- `player_achievement_stats`: one compact aggregate row per account for distances, coins earned, and successful gravity flips.
- `player_achievement_hazards`: one row per account and hazard ID, with encounter-run count and timestamps. No per-frame or per-spawn event log.
- `player_achievements`: one row per `(user_id, achievement_id, tier)`, with `unlocked_at`.

Both tables should have RLS enabled and direct client writes revoked. Users read only their own achievement state through an authenticated RPC. Nicknames are for display only.

Extend the existing `record_player_run` transaction/RPC so that when it accepts a *new* `run_id`, it also updates achievement aggregates and inserts any newly earned tiers. Return the newly unlocked achievement IDs/tiers in the same response. A retry of the same run must neither increment metrics nor grant a tier twice. This reuses the existing account save queue and avoids a second fragile client write.

Each completed run sends distance, coins earned, successful flips, and the distinct profile IDs encountered in the viewport. The existing unique run ID gates all aggregate updates, so retries do not double-count. The client retains only the run's small set of encountered hazard IDs; the database retains account aggregates, not a gameplay event stream. Coins earned are tracked separately from the wallet balance because spending must not reduce achievement progress. Existing distance progress is backfilled; historic coins spent, flips, and hazard encounters cannot be reconstructed and start at zero.

The game is still client-authoritative for gameplay. This makes saving consistent and retry-safe, not cheat-proof against a modified client; full anti-cheat would be a separate project. Rare collectibles that grant persistent value should use a separate idempotent immediate-event path when that gameplay is introduced, rather than waiting for run completion.

### 3. Client service and account lifecycle

`AchievementService` should:

- Load the signed-in account's unlocked tiers and aggregate progress on auth; clear visible state on sign-out/account switch.
- Evaluate progress for immediate in-run milestone toasts; show them as provisional until the completed run has been accepted by Supabase.
- Consume unlocks returned by the successful run-save RPC, then show confirmed awards in the post-run carousel.
- Avoid all achievement writes/queues for guests. No guest achievements should silently appear after sign-in.
- Keep an account-scoped read cache only for responsive UI, never as the source of truth for granting rewards.

The existing `AccountProgress` can either own the response handoff or emit a typed `run_saved` payload for the new service. Prefer a clear signal boundary over coupling achievement logic into HUD/gameplay code.

### 4. Menu and presentation

The authenticated-only Achievements menu shows visible locked/unlocked catalog rows and progress bars. Secret entries are omitted until unlocked. The post-run panel lets players page through confirmed achievements earned that run. A toast appears bottom-right when a tracked threshold is reached; while the run is unsaved it says “Milestone reached,” then the result panel reflects only server-confirmed unlocks.

During play, show a brief localized toast on a newly returned unlock. Do not make gameplay wait for the toast; the durable unlock is already saved. If the network save is pending, show it only once the server confirms it.

## Candidate achievement families (no thresholds committed)

- **Distance:** total account distance; best distance in one run.
- **Hazard mastery:** die to each hazard type; optional counts or tiers per hazard.
- **Challenge rivalries:** beat a challenge's creator, beat a prior personal best, beat distinct opponents, or finish ahead of N participants.
- **Future collection/rewards:** achievement tiers can reference unlock/reward IDs, without implementing purchases or inventory now.

## Implemented first phase

1. `202609260004_achievements.sql` creates the initial account-only achievement tables and distance catalog.
2. `202609260005_achievement_catalog_metrics.sql` adds the server-fetched catalog, coin/flip/hazard metrics, and the expanded idempotent run RPC.
3. The Godot client contains the account menu, live milestone toast, post-run award carousel, and compact run metrics.

Apply the achievement migrations in order on desktop: `202609260004`, then `202609260005`. The client now calls the expanded RPC signature, so both must be applied before testing run saves with this build.

Keep the next Supabase change as a new migration and provide its SQL for the desktop to run, like the pending challenge-library migration. This document does not apply any database changes.

## Open product choices for later

- Whether challenge achievements count only signed-in opponents or include guest nicknames. Account-linked opponents are safer and unambiguous; guest challenge records can remain leaderboard-only until identity/rules are decided.
- Whether public-visible achievements show precise progress or only the next target.
- Reward types and whether rewards are cosmetic, functional, or purchasable.
- Adding challenge-comparison, death-cause, campaign, or collectible-specific evaluators.
