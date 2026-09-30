# V2 lobby, start timeline, and return implementation report

Date: 2026-09-30

## Implemented

- Added migration `202609300002_v2_lobby_cycles.sql`. It introduces separate roster, course-content, lobby-cycle, and state revisions; binds ready to the current cycle, course content, and a per-player SHA-256 loadout fingerprint; invalidates that player's ready state when the fingerprint changes; preserves other players' ready and course acknowledgements across roster-only joins/leaves; makes identical manifest writes idempotent; and keeps cosmetic skin changes independent from ready.
- The migration makes host lobby opening and member return cycle-aware, records guest return separately, requires every active member to have returned and readied the current course before prepare, and adds a host-only kick RPC guarded by owner, cycle, user identity, and slot. Replaced V2 RPCs keep their V1 counterparts unchanged. V2 joins now require protocol 2 and game version `2.1.20260930.4`.
- Added bounded signaling diagnostics without SDP, ICE candidate, token, or channel contents. A room-scoped signal from an unknown member is queued for up to 4 seconds (maximum 32 messages) while a roster refresh runs. It is replayed only after backend membership is confirmed; offers are processed before queued ICE, and orphan ICE waits for the matching offer. Duplicate descriptions do not trigger another SDP operation. The automatic connection recovery remains in place.
- First transport connection and later reconnection now have separate diagnostics. Start diagnostics preserve local tick positions, first-step deadline lateness, remote sample ticks, and the first two seconds of presented local/remote positions.
- V2 simulation steps now target the shared round-clock tick with a maximum of 12 catch-up steps per physics frame. Remote tracks use the same round presentation clock, with bounded extrapolation and existing terminal-pose handling. The local runner is moved to the last peer draw position without changing its world position, z layer, collision, or simulation state.
- Results stay on each client until that client returns. A host's normal lobby opening does not broadcast navigation. Lobby UI reports who has not returned or readied and exposes host kick controls. A kicked client receives a reason over the peer link or learns its membership ended on room refresh.
- Added contract coverage for state-revision ordering, shared remote presentation time, replay after roster confirmation, and the 101% versus 100% 45-tick speed gap.

## Verification

- Confirmed migration numbering before adding `202609300002`; no applied migration was edited.
- `git diff --check` passed.
- The repository has no `godot`, `godot4`, `psql`, or `supabase` executable on `PATH`, and no matching executable was found under the project or standard Windows program directories. The Godot contract suite, import/parse, web export, SQL execution, and three-browser lifecycle run therefore could not be executed here.
- The migration has not been applied to any database. No deploy or push was performed.

## Findings and limits

The reported first attempts from both guests recovered after about ten seconds, while the host's first recorded peer creation was on attempt 2. An offer arriving before the host's refreshed roster remains a plausible cause, not a proven cause. The implementation now records signal acceptance/rejection reasons and roster revision, but the live case still needs a three-client run to establish whether the roster filter caused the loss or whether signaling delivery, channel readiness, SDP, or ICE did.

The 75 ms independent remote buffer has been replaced by a shared presentation tick. This removes first-sample arrival as a permanent per-player phase. The 100 ms extrapolation cap and jitter behavior still need measurements under direct and relayed links. No claim is made that networked identical runners stay within one pixel until the deterministic and three-client tests run. Individual speed and local authority remain intact, including the reported 101% versus 100% loadout difference.

Backend/user-flow behavior, migration syntax against the target PostgreSQL version, V1 and singleplayer regression, and export remain unverified because their required runtimes or live test environment were unavailable.
