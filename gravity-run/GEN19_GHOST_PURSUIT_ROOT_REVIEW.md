# Gen19 ghost pursuit root review

Status: ROOT_APPROVED for scoped ghost pursuit/fallback release, 2026-10-07. This approval does not claim the barrel or density feedback is resolved.

Root inspected the shared pursuit trajectory/lane snapshot, world ledger validation and baseline immutability, SP source-to-resolved fallback dispatch with normal spawn horizon/dedup, and reviewed the draft 202610070001 migration against .002. SQL changes only add the Gen18/.14 and Gen19/.15 compatibility tuples and achievement receipt version allowlists; authentication, wallet and idempotency logic are unchanged.

Root independently ran actual main fallback scene, world activation contract and release version contract: all exit 0/failures 0. Earlier reviewed runtime capture demonstrates lane transition, locked pursuit, overtaking and exit in actual main at 250/500/750; selected full-manifest route and frozen Gen17/18 checks pass per durable evidence. No connected MP or physical mobile gameplay is claimed.

The experimental Gen19 barrel placement changes were withdrawn. The final candidate has no demonstrated improvement in overall density or largest empty gap; these concerns remain open. This release delivers the corrected ghost and consistent SP/MP fallback behavior. Comparisons against unreleased Gen18 are not proof of improvement over public Gen17.

Stage only reviewed gameplay/version/test/migration/report files and selective main.gd feature hunks, excluding unrelated capture/pacing diagnostics and other dirty files. Complete Azure push, linked migration history/dry-run/apply/post-history, clean exact-commit Web export and Pages publication. Root must independently verify final workflow/head, both BUILD_ID/loaders and downloaded PCK bytes/hash before completion notification.

## Independent root live verification

Workflow 37651709969 completed/success at exact Pages head dab7ce92acd174fe1ff69c164bdb0c8607d8e322. Both public BUILD_ID markers and root/game loaders returned HTTP200 with shared-ghost-gen19-def4540-20261007. Independently downloaded public PCK is 3,610,812 bytes, SHA256 7892232EB87E958B9DA8329C02804336CE95E22B5F0C410D00C5448F8F37BD50, matching the clean exact-commit export. Azure remote matched report head aaa054eb2c2d7172d8662070a0a9475d65dbefcf; gameplay source def4540919af7cf02de19bb09d22d68cc0b2f569. Migration completed per linked-history evidence. Ghost release complete; barrel/density feedback remains unresolved.

