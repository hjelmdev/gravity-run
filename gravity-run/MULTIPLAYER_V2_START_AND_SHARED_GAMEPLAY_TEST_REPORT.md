# Multiplayer V2 start and shared gameplay — implementation report

Date: 2026-09-29  
Source base: `a014283` (`Fix V2 match start recovery and room expiry`)  
Build: `2026.09.29-v2-start-course-r2`  
GitHub Pages source: `51d6c2b` (`Deploy V2 diagnostics export size limit`)

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
- Web PCK export succeeded. PCK size: 1,058,228 bytes. SHA-256: `FD5E82718C8DAF908982D27109B5DD34B38122BBC7ADEAA40D4CCB31FA4B7F62`.
- GitHub Pages run `#89` for commit `51d6c2b` completed successfully. V2's game index now points to the versioned `r2` PCK.

## Still requires a real paired browser run

This repository does not currently have an automated two-client WebRTC/browser harness. The required paired host/guest trace has not yet been collected, so the original production failure's exact RPC rejection point is still unverified. The current browser session only proved that the game and menu load; it did not reach a room or download a lobby report.

Still to verify with two separate browser identities:

- Host and guest both download valid, uniquely named JSON from the lobby; compare room ID, round ID, generation, peer mapping, manifest hash, and build ID.
- Both clients enter the match, report scene-ready, and begin tick 0 on the same round and manifest. Repeat with a third client.
- Rejection/timeout returns both sides to the lobby with the same reason; run ten rematches.
- Same seed comparison against V1, real hazard/world destruction synchronization, and V1/single-player regression.
- Confirm which Supabase migration/version is active on the production project as part of the paired trace; it was not queried during this implementation pass.

The V1 root page and root game bundle were not included in the V2-only deployment commit.
