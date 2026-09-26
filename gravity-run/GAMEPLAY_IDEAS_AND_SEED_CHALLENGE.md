# Gameplay ideas and implementation notes

## Ideas to explore

### Character and inventory

The player wants a character/equipment view inspired by classic RPGs: a pixel-art character preview, visible equipment slots, and a summary of stats derived from equipped items. The eventual slot layout may include two rings, helmet, chest, legs, boots, gloves, belt, necklace, and two trinkets; it does not need to ship with every slot.

Items should be shown in a bag/grid and moved to compatible slots, either by drag-and-drop or by selecting a slot and choosing an item from a list. This is also a character-management view, not just an inventory screen.

Recommendation: first decide what item stats mean in Gravity Run and what progression is fun. Then implement a data-driven item/slot model and a small loadout (for example helmet, chest, boots) before building the full bag UI. Keep slots extensible. Drag-and-drop is optional; slot-first selection is a simpler first interaction. Equipment that changes run performance may need separate leaderboard rules or visible loadout information.

### Live multiplayer (2a)

Players create or join a session, wait in a lobby, and start together on the same course. Each player is eliminated when they die.

Recommendation: defer this until the single-player rules and seeded runs are stable. It requires session discovery/signaling, connection recovery, synchronization, and a clear authority model. Browser P2P uses WebRTC and requires signaling; Godot's native WebRTC support also has a separate extension requirement. See [Godot WebRTC documentation](https://docs.godotengine.org/en/stable/tutorials/networking/webrtc.html).

### Seed challenge (2b)

After a run, show a shareable challenge code. A friend enters it from the menu and plays the same course, with distance as the comparison score.

Recommendation: start here. It reuses the course generator and avoids real-time networking. Initially compare distance only. Coin placement/rewards are not part of challenge equivalence; the player may still collect coins for their own account. Seed all randomness that affects hazards and terrain, and keep cosmetic randomness separate. Godot's `RandomNumberGenerator` supports reproducible sequences from a fixed seed; see [Godot random number generation](https://docs.godotengine.org/en/stable/tutorials/math/random_number_generation.html).

## Generator-version decision

A seed reproduces the same result only while the generation rules and content catalog remain the same. Adding a hazard to the random-selection pool, changing weights, or consuming random values in a different order can change later events for the same seed. A seed does not store a snapshot of the generated course.

Every run gets a seed and a shareable code uses `GR2-<seed>`. The prefix identifies the complete generation algorithm/catalog version; old codes are intentionally rejected rather than preserving old generation behavior. Coins are intentionally outside the first version's comparison guarantee.

## Seed-challenge implementation status

- Every run now gets a seed. The menu accepts a friend's challenge code; starting a random challenge explicitly before a run is not required.
- Codes use a generator-version prefix and positive numeric seed (`GR2-...`).
- Rule-configured challenges use an opaque `GC-...` code whose stored definition contains the generator version, seed, serialized ruleset and creator nickname. The code itself stays short enough for a link.
- The code seeds `CourseGenerator`, which determines hazard/terrain events, including each event's sampled barrel-speed factor.
- Shared web links append the challenge code as `?challenge=...` to the GitHub Pages root. The wrapper page serves as usual; the game reads the parent URL through Godot's `JavaScriptBridge` and opens the join screen with the code prefilled. No separate redirect server or Pages routing setup is required.
- A normal run offers an optional share action at run end; a joined challenge shows its code there. A drawn copy icon avoids reliance on a font glyph.
- The challenge menu offers Easy/Normal/Hard factors and per-hazard inclusion. Creating one stores the exact ruleset before starting; joining a `GC` link validates the version and rules fingerprint, previews creator/rules/top-five records, then starts on confirmation.
- This remains a local/manual friend challenge: there is no matchmaking or P2P session.
- Automated tests cover repeated event sequences, challenge-code parsing/version validation, and barrel-speed forecasting.

### Per-seed records proposal

Do not put results in the code or seed. Basic `GR2` results are stored by generator version + seed; configurable challenge attempts are stored by opaque challenge code, keeping different rule sets and challenge instances separate. Store each attempt for history, but show one row per nickname with that name's best distance and attempt count. Guest rows contain no player/account UUID: the normalized nickname is their board identity. Registered nicknames are reserved, but guests can still impersonate or collide with another guest's nickname, so this is suitable for casual friend challenges, not prizes or trusted rankings. A normal run is published only when the player chooses to share; the end screen clearly says the result is public. Joining a shared challenge also exposes the top-five results during play.

The HUD chase strip plots the current top-five distances on a shared distance axis, shows the player's live position, and counts down to the next record ahead. It uses the reserved top/bottom HUD bands, keeping labels and the pause button clear of the cyan track boundaries. Completing a joined challenge automatically saves that attempt after the end screen discloses that the nickname and score are public; ordinary runs are only sent if the player chooses the share action.

## Shared course-generation contract

`CourseGenerationRuleset` is the data-only input to encounter generation. It can allowlist hazard-profile IDs and scale event density, hazard size, lane alternation, reaction margin, and per-profile weights. Each hazard profile supplies its own lane constraints and threat forecast, so future hazards (for example birds or torpedoes) can join the same planner rather than requiring hazard-specific rules in the generator. The route-feasibility check remains authoritative: impossible placements are shifted/rejected, and even the safe fallback may use only profiles allowed by the active ruleset.

`CourseRunDefinition` binds scenario ID, generator version, seed, and ruleset into one run contract. Its course identity is generator version + ruleset fingerprint + seed; the scenario label does not change course identity. That supports a fixed campaign resource such as `campaign-5-1` with a permanent seed/ruleset, while an endless run creates a new seed using the same default ruleset. Campaign objectives and completion conditions belong above this generation contract, so the same deterministic course system can serve endless challenges and finite objective-driven stages.

The planner uses fixed reference inputs (750 px/s planning speed, 900 px conservative track height, and an 820 px hazard spawn lead) rather than the current viewport or runtime speed. This is necessary because a seed alone is insufficient if screen dimensions or event-spawn timing can change the planned sequence. The taller reference is deliberately conservative for typical landscape/expanded viewports. These deterministic-input changes are why the generator version is now 2.

`GR2` continues to mean the standard ruleset. `GC` codes refer to immutable Supabase challenge definitions whose fingerprint is recomputed and checked by the client before play. Campaign definitions remain authored locally and can use the same run contract without conflating campaign objectives with endless distance scoring.

## Suggested order after this increment

1. Seed challenge (2b), including reproducibility tests.
2. Small data-driven equipment/loadout foundation, after choosing item stats and progression.
3. Live P2P multiplayer (2a), after the run simulation and challenge rules are stable.

### Supabase for shareable rule-based challenges

The Pages deep link itself needs no Supabase URL routing or extra service: the
game reads `?challenge=...` from the wrapper page. Supabase is needed for the
next layer: saving a challenge's immutable ruleset definition and isolating its
submitted runs/leaderboard from other seeds or rulesets.

An additive migration is prepared at
`supabase/migrations/202609260002_seed_challenge_definitions.sql`. It adds
public, nickname-only challenge definitions and RPCs to create/read a challenge
and submit/read that challenge's leaderboard. It does not replace the current
seed-score RPCs or store account UUIDs. Run it in the Supabase SQL Editor only
when the client implementation for these RPCs is ready; no dashboard settings,
OAuth providers, or hand-created tables are needed. Existing seed challenge
rows and RPCs are left intact.
