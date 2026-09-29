# Multiplayer V2 start and shared gameplay — implementation report

Date: 2026-09-29
Source base: `d3a4d32` (`Fix V2 peer map and start recovery`)
Build: `2026.09.29-v2-start-course-r4`
GitHub Pages source: `7d59267` (`Deploy V2 start failure fix r4`)

## Implemented

- Corrected the local WebRTC peer ID mapping so session identity, transport ID, and database player slot must agree. Added fail-fast mapping checks at activation and gameplay transitions.
- Froze a host round descriptor with roster, peer map, round ID, generation, manifest hash, seed, and course length. Guest preparation consumes that descriptor instead of rebuilding one from mutable lobby state.
- Added a prepare-received barrier before either side requests the match scene, plus the existing scene-ready and start-ack barriers. Prepare retries and timeouts now return an explicit failure reason.
- Added timestamped prepare, validation, scene-ready, commit, peer mapping, and start events to V2 diagnostics. Added diagnostics download to the V2 lobby as well as the match screen.
- Added an 8 MiB diagnostics export limit that removes the oldest frame samples first, then oldest events, and records truncation counts in the downloaded JSON.
- Added `RaceCoursePresentation` and switched V1/V2 course construction to real terrain/hazard scenes and `CourseSurfaceRenderer`; removed V2 primitive-only course drawing. V2 runner uses the shared resolved speed/cooldown profile values.
- Kept the V1 GitHub Pages root assets unchanged. Published V2 via its own `/multiplayer-v2/` path and a versioned PCK filename.
- Fixed the r3 host start blocker: `prepare_as_host` requires `Array[int]`, so the production path now converts `PackedInt32Array` into a typed array without erasing its element type. The coordinator logs the type and exact peers passed.
- Added regression checks for one guest, two guests, and solo through the production conversion. Added idempotent guest lobby reset, guest `PREPARE_FAILED`, scene-preparation failure reports, accurate response-generation/phase diagnostics, monotonic UTC stamps, and a current runtime snapshot in diagnostics exports.
- Added V2-only migration `202609290003_require_all_v2_players_ready.sql`. The server locks active membership rows, requires every active member to be ready on the room manifest, and returns only that active roster. The shared room-payload function used by V1 remains unchanged.

## Automated checks run

- Godot 4.7.2 editor import/parse scan completed without script parse errors.
- `tools/multiplayer_v2/contract_test.gd` passed, including prepare barriers, frozen descriptor, runner stats, and oversized diagnostics trimming.
- `tools/course_manifest_test.gd` passed.
- `tools/race_course_presentation_test.gd` passed.
- Baseline `r2` export: 1,058,228 bytes, SHA-256 `FD5E82718C8DAF908982D27109B5DD34B38122BBC7ADEAA40D4CCB31FA4B7F62`; Pages run #89 published it before the r3 fix.
- r4 import/parse and all three automated tests passed. The only Godot console warning was the existing Windows root certificate-store warning; no script parse/runtime errors were found.
- r4 Web PCK export succeeded at 1,069,044 bytes. SHA-256: `4B747AF68AD83E97D2FFCA315275FF5F4ACC5A274A9FAF195E39FFB699DB9ADD`.
- Native headless load of the exported r4 PCK exited successfully with no script or pack-load errors.
- The live Supabase function was inspected before replacement. Migration `202609290003_require_all_v2_players_ready.sql` then completed successfully in project `qtuyiammppulmxhyaesh`; a read-back query confirmed the all-active-members readiness check and active-only roster payload. V1's shared payload function was not changed.

## Still requires a real paired browser run

The paired `r2` host/guest diagnostics identified the first failure: host rejected the frozen descriptor three times as `peer_map_mismatch_for_slot:1`, before sending `PREPARE_ROUND`. The host then returned the room to lobby; the guest rejected host `RETURN_TO_LOBBY` and heartbeat packets because its local generation had not advanced. Supabase JSON represented `player_slot` as `1.0`/`2.0`; peer-map construction used those float strings as keys, while validation looked them up as integer strings. The code now normalizes slot IDs to integers, guards room snapshots against generation/phase regression, assigns `attempt_id` before the backend request, and propagates a lasting abort reason to both clients.

The targeted peer-map, production typed-array boundary, diagnostics, abort, and return-to-lobby tests pass locally. The full live two-client flow still needs rechecking on `r4` after deployment.

## r4 deployment and paired verification

V2-only Pages commit `7d5926742a4ee3f2b06cfef1ce9de9fab2c64def` deployed successfully in GitHub Pages run `#91`. A cache-busted `/multiplayer-v2/` page loaded to the game menu. V1 root assets were not included in the deployment commit.

A paired host/guest start must still verify the complete PREPARE → scene-ready → COMMIT → START_ACK → round_started → bidirectional samples chain. The full flow has not yet been re-run with two real browser identities.

Still to verify with two separate browser identities:

- Host and guest both download valid, uniquely named JSON from the lobby; compare room ID, round ID, generation, peer mapping, manifest hash, and build ID.
- Both clients enter the match, report scene-ready, and begin tick 0 on the same round and manifest. Repeat with a third client.
- Rejection/timeout returns both sides to the lobby with the same reason; run ten rematches.
- Same seed comparison against V1, real hazard/world destruction synchronization, and V1/single-player regression.
- Exercise the production readiness function with lobby cases: one ready plus one active unready must reject; all active ready on the same manifest must accept; a stale inactive membership row must not enter the frozen roster; one ready host may start solo.

The V1 root page and root game bundle were not included in the V2-only deployment commit.
