# Multiplayer V2 – implementation and test status

Date: 2026-09-29
Branch: `codex/multiplayer-v2`
Godot: 4.7.2.stable, native Windows build

## Implemented

- V2 entry from the game hub, isolated lobby and match scenes, separate service/API branch and Supabase RPC names.
- Additive `network_mode` room isolation, V2 protocol version, room session ID, lobby generations, five-player capacity, signaling policy split and V1 RPC guards in `supabase/migrations/202609280004_multiplayer_v2_isolation.sql`.
- Guest-to-host WebRTC negotiation, reliable control RPCs, unreliable ordered position samples, connection generations, stale signaling rejection, heartbeats and bounded reconnect attempts.
- Per-player local fixed-step runner, independent world simulation, remote interpolation, spectator selection and separate 30/60 Hz sample rate control.
- Prepare/commit/start barrier, host terminal/result coordination, result and terminal acknowledgements, shared barrel claims, generic entity commits and reconnect world baselines.
- V2 diagnostic ring buffers and a local JSON save button. The lobby accepts a course seed so a V2 course can be repeated.

## Checks run

| Check | Result |
| --- | --- |
| Godot editor import and script parsing | Pass |
| Headless game startup | Pass |
| `tools/multiplayer_v2/contract_test.gd` | Pass: protocol, clock, remote track, start barrier, shared entity claims, multi-HP destruction, reconnect baseline, deterministic world hash and local runner contracts |
| `tools/webrtc_native_test.gd` | Pass: native WebRTC peer and data-channel initialization |
| Existing `tools/multiplayer_lobby_contract_test.gd` | Pass |
| Existing V1 lobby UI smoke test | Pass |

Commands (from `gravity-run/`):

```powershell
& 'E:\Utveckling\Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path . --quit
& 'E:\Utveckling\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/multiplayer_v2/contract_test.gd
& 'E:\Utveckling\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/webrtc_native_test.gd
& 'E:\Utveckling\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/multiplayer_lobby_contract_test.gd
& 'E:\Utveckling\Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://tools/multiplayer_lobby_smoke_test.tscn
```

## Not run

- The additive V2 isolation migration (`202609280004`) and the V1 countdown payload compatibility fix (`202609290001`) have been applied to the linked production Supabase project. Schema presence and V1 room preservation were verified. Live RLS/RPC behavior still needs multiplayer testing.
- No real three-process host-plus-two-guests WebRTC session was run. The native smoke test only initializes the extension; it does not verify SDP, ICE, RPC delivery, reconnect or NAT traversal.
- A web export was generated for the isolated Pages test path. No interactive browser or visual smoothness assessment has been completed. Headless checks cannot establish camera smoothness, input feel, browser throttling behavior or visual parity.
- No full lobby-to-results gameplay session, ten-round rematch run, TURN/NAT test or network impairment matrix was run.
- V2 supports entering a repeatable course seed. The existing V1 create flow still chooses its seed automatically, so a same-seed V1/V2 A/B session needs a V1 test seed override or a seed supplied by the existing test setup.

Treat the code as an implemented experimental branch that has passed static/headless contracts, not as a backend-deployed or end-to-end validated multiplayer release. Apply the migration and run the live host/guest/browser matrix before using it for comparison conclusions.
