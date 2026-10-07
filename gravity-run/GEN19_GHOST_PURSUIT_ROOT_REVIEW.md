# Gen19 ghost pursuit root review

Status: ROOT_APPROVED for scoped ghost pursuit/fallback release, 2026-10-07. This approval does not claim the barrel or density feedback is resolved.

Root inspected the shared pursuit trajectory/lane snapshot, world ledger validation and baseline immutability, SP source-to-resolved fallback dispatch with normal spawn horizon/dedup, and reviewed the draft 202610070001 migration against .002. SQL changes only add the Gen18/.14 and Gen19/.15 compatibility tuples and achievement receipt version allowlists; authentication, wallet and idempotency logic are unchanged.

Root independently ran actual main fallback scene, world activation contract and release version contract: all exit 0/failures 0. Earlier reviewed runtime capture demonstrates lane transition, locked pursuit, overtaking and exit in actual main at 250/500/750; selected full-manifest route and frozen Gen17/18 checks pass per durable evidence. No connected MP or physical mobile gameplay is claimed.

The experimental Gen19 barrel placement changes were withdrawn. The final candidate has no demonstrated improvement in overall density or largest empty gap; these concerns remain open. This release delivers the corrected ghost and consistent SP/MP fallback behavior. Comparisons against unreleased Gen18 are not proof of improvement over public Gen17.

Stage only reviewed gameplay/version/test/migration/report files and selective main.gd feature hunks, excluding unrelated capture/pacing diagnostics and other dirty files. Complete Azure push, linked migration history/dry-run/apply/post-history, clean exact-commit Web export and Pages publication. Root must independently verify final workflow/head, both BUILD_ID/loaders and downloaded PCK bytes/hash before completion notification.
