# Root review — Web right-edge PNG capture

2026-10-06: REVIEW_CHANGES_REQUESTED. Read capture component, MP integration diff and Web package evidence. Independent root validation of the actual downloaded ZIP passed CRC, decoded every numbered PNG and checked dimensions against metadata: 25 frames / 17280000 retained raw bytes.

Capture is opt-in, serial post-draw readback, one-second/30-frame/raw and ZIP bounded; normal JSON export remains separate. Browser fixture download is actual Chrome evidence; actual MP controls have native touch integration evidence, not a live authenticated browser match. Readback overhead is recorded and must remain explicit.

Two fixes requested before release approval:

1. Cave ridge metadata currently duplicates the wrong parallax constants (0.03/0.035 versus renderer 0.16/0.07) and wrong right endpoint phase formula; derive bounded actual fragment/last vertices through a shared renderer helper or exact same formula with regression. Wrong metadata would misdiagnose precisely the reported edge.
2. MP UI detects memory cap by searching translated completion text for English 'memory limit'. Use structured cap reason/state so Swedish displays caps correctly.

Luna owns corrections and targeted current-tree verification. No source/API/generator/database gameplay changes; preserve unrelated dirty work. Root approval remains pending; publish only after reviewed corrections.

## Release approval

Reviewed the corrected shared `BiomeRenderer.cave_ridge_diagnostic_samples` source: renderer and capture use identical phases/endpoints per fragment. The completion reason is structured and MP no longer inspects translated prose. Current actual-renderer contract and MP touch tests passed; Chrome downloaded the matching current fixture ZIP. Root independently checked its CRC and all 26 PNG dimensions against metadata, completion reason complete.

**APPROVED for scoped diagnostics release.** Commit/push only reviewed component, MP UI/layout, shared ridge diagnostics helper, locales, tests and task documentation. Preserve unrelated dirty files. No API/generator/database changes. Clean exact-commit export and Pages-root publication required; final acceptance includes workflow/head, both BUILD_ID/loaders and independent downloaded public PCK hash. No claim that cave flicker itself is fixed.

## Independent final verification

Root took over when Luna hit model capacity. Reviewed source commit 8278c35 was already on Azure; clean export and scene-test logs were present, and prepared Pages commit 8140f42 had not been pushed. Root pushed that commit and verified workflow 37440107248 completed/success for exact head 8140f42. Both BUILD_ID and root/game loaders return HTTP200 with right-edge-capture-8278c35-20261006. Independently downloaded public PCK: 3352912 bytes / SHA256 E29B56A1D849D82DF4D4A937A522D76AC6876B42BE06F838BE1C8655D0448AFD, matching clean export. Release accepted. No database/API/generator changes. Cave flicker remains unresolved; user can now capture browser evidence as PNG+JSON ZIP.
