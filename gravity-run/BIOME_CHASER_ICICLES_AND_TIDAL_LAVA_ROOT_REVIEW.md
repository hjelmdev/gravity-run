# Gen17 biome encounters — root review

Status: ROOT_APPROVED (2026-10-06). Corrected implementation is approved for scoped release, including mobile seed-field integration.

## Evidence inspected

Root inspected the shared models, SP adapters, generator/profile threat intervals, shared coin planner, manifest validator, world collision code, route fixture and SQL migration diff. Root viewed GPU phase fixtures for icicles and lava. The isolated SQL gate passed under authenticated role with synthetic account data and rollback. Comparing migration `.002` against `.001` shows only the intended .13/Gen17 compatibility tuple and generator receipt allowlist additions; wallet/auth/idempotence rules are unchanged.

## Required corrections

1. Moving ghost swept collision was applied to stationary legacy ghosts too. Preserve original SP/MP variant-0 contact and warning/danger/expiry boundaries; new path only for chaser variant 1. Frozen manifest hashes alone do not prove unchanged runtime behavior.
2. Manifest build filters unsafe Gen17 events, but SP raw event adapters and coin planning bypassed this filter. Use the same versioned resolved/filter pipeline and enough forward terrain horizon for the whole chaser corridor. Check a rejected event is absent in both modes and collectible exclusions agree.
3. Icicle expiry can yield a zero ending Rect2 in legacy rock sweep code, incorrectly calculating motion towards world origin. Clamp the new variant's active interval and add supported/gap expiry tests against a distant runner. Preserve variant-0 rock behavior.
4. Route fixture initially flipped at the first tick, before a visible warning. Add real reaction margin from warning and test representative pool phases at 250/500/750, keeping all hazards and real forward simulation.
5. Initial icicle image was the original chunky rock silhouette tinted blue. Give the icicle distinct pointed ice art/cold impact presentation, preserving ordinary rocks and keeping contact aligned with visible ice.
6. Existing GPU phase-panel fixtures are useful but are not actual gameplay. Capture selected actual SP/shared MP presentation views with runner/biome/terrain in landscape and portrait before claiming gameplay visual verification.

## Release constraints

Stage only new feature hunks from main.gd; exclude older uncommitted render/pacing/blocked diagnostic work. Preserve approved gravity-flip audio, recorded death sound, cave/touch/capture behavior. New Gen17/API .13/manifest10 requires only the reviewed version-gate migration. After corrected review passes, scoped Azure commit/push, linked migration verification, clean exact-commit export, Pages and independent root workflow/BUILD_ID/loader/public-PCK-hash verification.

Cohort evidence is 40 seeds at 45,000px, with 78 new variants but total hazards down 6.5% and coins down 8.5%; no density increase is claimed. Representative routes are not all-seed solvability. No real connected multiplayer or mobile-browser performance evidence is claimed from offline fixtures.

## Corrected review and approval

Root inspected the corrected variant-specific legacy ghost path, clamped icicle active interval, shared runtime event filter/SP adapters/coin catalog, reaction route regressions and mobile field callbacks. Root independently ran the shared encounter suite and mobile seed scene integration suite: both exit 0, failures 0. Godot reports resource cleanup warnings at test shutdown; these are not assertion failures or a measured gameplay leak.

Root viewed the updated pointed-ice phase image and actual main haunted gameplay image with HUD/runner/biome. Pool/chaser have actual main captures; icicle remains covered by phase views and real-time route/model tests. Connected MP, real phone keyboard/paste/cancel, and portrait actual gameplay are not independently verified. This limited visual evidence is accepted for this release, without claiming device validation. Existing mobile parent-page entry implementation is reused, with SP GR parsing and MP integer validation retained.

All concrete correctness findings above are resolved. Publish only feature-scoped hunks and reviewed .002 migration. Release verified: workflow 37528383927 completed/success for Pages head 4333b4b0d82c809782267ef59e1e97d518f3f602; both BUILD_ID markers and root/game loaders use biome-chaser-icicles-gen17-a219fa7-20261006. Public PCK is 3,533,324 bytes, SHA-256 8829701B162DE096F44D4A5DEDDDE98A0A4EE94BAB8AEFDB3304AFCE57344845, matching the clean exact-commit export.


Azure source commit a219fa78d1011307bb050d1ee9fbff535b989aa3 and live migration 202610060002 are confirmed. The docs/game active Pages bundle and root loader were published in Pages commit 4333b4b0d82c809782267ef59e1e97d518f3f602. No online connected match or physical phone keyboard test is claimed.

## Independent root publication verification

Root independently verified workflow 37528383927 completed/success at exact Pages head 4333b4b0d82c809782267ef59e1e97d518f3f602. Root and game BUILD_ID plus both loaders returned HTTP 200 and the expected biome-chaser-icicles-gen17-a219fa7-20261006 marker. Independently downloaded public PCK is 3,533,324 bytes with SHA256 8829701B162DE096F44D4A5DEDDDE98A0A4EE94BAB8AEFDB3304AFCE57344845, identical to the clean export. Azure remote head was verified at documentation commit 76bf47e5e8b84ff4dfcb449b9f842230c5757878. Follow-up automation paused on completion. User device input testing remains as documented.

