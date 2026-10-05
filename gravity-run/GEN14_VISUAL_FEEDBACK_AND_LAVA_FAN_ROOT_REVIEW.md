# Root review — Gen14 feedback / Gen15 lava fan

2026-10-05: **CHANGES_REQUESTED. No release approval.** Luna resumed with concrete review corrections.

Reviewed the actual model, builder, manifest validator, camera and hub diffs, route tests and actual SP volcano / MP crack GPU captures. Six flame-tailed projectiles and deeper crack branches are visually clear. Gen14 trajectories remain in an explicit legacy branch.

Required before approval:

1. Cave motion evidence: 16 one-pixel steps cover only 16px and moving pixel ratios have neither motion compensation nor an assertion. Capture actual SP/MP realistic fractional camera motion across several cell/chunk boundaries and assess expected parallax versus blink/discontinuity, particularly at the right edge. Keep the reported browser flicker explicitly unresolved if not reproduced; do not claim a renderer fix without evidence.
2. Camera continuity: exercise actual match/presentation lifecycle preparing/countdown/START/running/spectator, compared with actual SP transforms at equal viewport sizes. Current helper test labels samples with lifecycle names but does not exercise those phases.
3. Fan safety: inspect actual terrain/support across the complete Gen15 projectile envelope, including side ceilings/gaps; center ceiling_y alone does not establish a safe lane across that span. Add adversarial terrain checks and full-manifest routes for a small documented Gen15 cohort, with coin/risk budgets. Preserve Gen14 hashes.
4. Migration rollback evidence: exercise changed Gen15 coin-round/receipt/achievement gates and retries/idempotency, in addition to room creation. No live migration until reviewed.
5. Translate the new seed placeholder and tooltip through the existing locale files.

Luna owns these corrections and the status update. Preserve unrelated dirty files, touch handling and selected death recording; run bounded serial Godot tests and clean up only owned processes.

## Follow-up review, 2026-10-05 23:41 local

Read the new actual match-scene camera fixture, full-manifest route cohort and local rollback SQL test. The corrected lane-mask mapping and reconstructed profile threats address the prior fixture failures. Five volcanoes across three seeds pass at 250/500/750; projectiles are active at 250/500 while 750 passes before eruption. Accept that documented limitation alongside phase-independent geometry validation. Camera evidence is a deterministic scene fixture, not a live authenticated room. Swedish strings are supplied. Longer native cave captures still do not reproduce the browser report; cave remains explicitly unresolved.

**One concrete release correction remains:** full-envelope safety is currently checked only by manifest validation. Builder emits unsafe Gen15 volcanoes first, so unsuitable side terrain can reject an entire random course. Filter those volcanoes deterministically using the fully resolved terrain before planning collectibles and hashing. Retain validator defense. Account for terrain boundaries and projectile/runner widths rather than relying solely on 8px support samples and projectile-center clearance. Add regression evidence and rerun relevant freeze/routes. Luna has received this correction; approval remains pending.

## Follow-up source review, 2026-10-05 23:56 local

Builder now filters Gen15 volcanoes before CoinPlanner/hash; legacy generation is untouched. Reviewed the shared exact gap/boundary checks and subsequent conservative full-span check: analytic fan-envelope top must clear the lowest ceiling anywhere across the expanded runner corridor by runner height plus 24px. This also addresses interior ballistic minima missed by endpoint-only checks. Source correction accepted, pending plateau regression and final targeted test confirmation plus a short independent root check. No live release approval yet.

Compared migration .004 directly with .003: only the new API .11 / generator 15 allowlists change in room creation, coin-round registration and achievement receipt functions. Existing authentication, row locks, journal/settlement behavior and account gates remain intact. Scoped SQL review accepted with documented local rollback verification; live history must still be checked during release.

## Release approval, 2026-10-06

**APPROVED for scoped release.** Luna added the interior-apex plateau regression; targeted filter, full shared lava world and Gen14 freeze tests passed. Root independently ran the actual `lava_shared_world_test.tscn --gen15-filter-only`: exit 0, `failures=0`, unsafe volcano removed while terrain and replanned coins remain. The owned root process exited and was bounded to 45 seconds. Source/SQL/visual review findings are addressed. Preserve the explicit unresolved cave-flicker limitation.

Proceed with scoped Azure commit/push, reviewed .004 migration with linked-history verification, clean exact-commit Web export and Pages root publication. Final acceptance still requires workflow/head, both BUILD_ID/root/loader and independently downloaded public PCK hash verification.
