# Multiplayer V2 start and shared gameplay — implementation report

Date: 2026-09-29
Source base: `a014283` (`Fix V2 match start recovery and room expiry`)
Build: `2026.09.29-v2-start-course-r3`
GitHub Pages source: `7f773d9` (`Deploy V2 peer map start fix`)

## Implemented

- Corrected the local WebRTC peer ID mapping so session identity, transport ID, and database player slot must agree. Added fail-fast mapping checks at activation and gameplay transitions.
- Froze a host round descriptor with roster, peer map, round ID, generation, manifest hash, seed, and course length. Guest preparation consumes that descriptor instead of rebuilding one from mutable lobby state.
- Added a prepare-received barrier before either side requests the match scene, plus the existing scene-ready and start-ack barriers. Prepare retries and timeouts now return an explicit failure reason.
- Added timestamped prepare, validation, scene-ready, commit, peer mapping, and start events to V2 diagnostics. Added diagnostics download to the V2 lobby as well as the match screen.
- Added an 8 MiB diagnostics export limit that removes the oldest frame samples first, then oldest events, and records truncation counts in the downloaded JSON.
- Added `RaceCoursePresentation` and switched V1/V2 course construction to real terrain/hazard scenes and `CourseSurfaceRenderer`; removed V2 primitive-only course drawing. V2 runner uses the shared resolved speed/cooldown profile values.
- Kept the V1 GitHub Pages root assets unchanged. Published V2 via its own `/multiplayer-v2/` path and a versioned PCK filename.

## Automated checks run

- Godot 4.7.2 editor import/parse scan completed without script parse errors.
- `tools/multiplayer_v2/contract_test.gd` passed, including prepare barriers, frozen descriptor, runner stats, and oversized diagnostics trimming.
- `tools/course_manifest_test.gd` passed.
- `tools/race_course_presentation_test.gd` passed.
- The baseline `r2` Web PCK export succeeded at 1,058,228 bytes. SHA-256: `FD5E82718C8DAF908982D27109B5DD34B38122BBC7ADEAA40D4CCB31FA4B7F62`.
- GitHub Pages run `#89` for commit `51d6c2b` deployed the versioned `r2` PCK before the `r3` fix.

## Still requires a real paired browser run

The paired `r2` host/guest diagnostics identified the first failure: host rejected the frozen descriptor three times as `peer_map_mismatch_for_slot:1`, before sending `PREPARE_ROUND`. The host then returned the room to lobby; the guest rejected host `RETURN_TO_LOBBY` and heartbeat packets because its local generation had not advanced. Supabase JSON represented `player_slot` as `1.0`/`2.0`; peer-map construction used those float strings as keys, while validation looked them up as integer strings. The code now normalizes slot IDs to integers, guards room snapshots against generation/phase regression, assigns `attempt_id` before the backend request, and propagates a lasting abort reason to both clients.

The targeted peer-map and snapshot-order tests pass locally. The full live two-client flow still needs rechecking on `r3`.

## r3 deployment and verification

- Local Web PCK export succeeded at 1,063,988 bytes. SHA-256: `257E5127858947A86125AA9D5C2323F011AD33DA98DF62CB9B737FF31DF30044`.
- V2-only Pages commit `7f773d9b97984a6f0da935575819c7fd5c4008ee` was deployed by GitHub Pages run `#90`, which completed successfully. The deployed app remains at `/gravity-run/multiplayer-v2/`; the V1 root assets were not included in the deployment commit.
- The deployed V2 page loads in the in-app browser. A paired host/guest start has not yet been re-run against r3, so this confirms availability, not that the live multiplayer round now completes.

Still to verify with two separate browser identities:

- Host and guest both download valid, uniquely named JSON from the lobby; compare room ID, round ID, generation, peer mapping, manifest hash, and build ID.
- Both clients enter the match, report scene-ready, and begin tick 0 on the same round and manifest. Repeat with a third client.
- Rejection/timeout returns both sides to the lobby with the same reason; run ten rematches.
- Same seed comparison against V1, real hazard/world destruction synchronization, and V1/single-player regression.
- Confirm which Supabase migration/version is active on the production project; it was not queried during this implementation pass.

The V1 root page and root game bundle were not included in the V2-only deployment commit.
