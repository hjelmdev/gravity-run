# Gen19 ghost render interpolation status

Status: REVIEW_READY. A presentation-only correction is implemented in shared SP/MP ghost rendering. Simulation ticks, phase authority, collision geometry, activation/ledger, generation, and network state remain tick-based and unchanged.

## Scope and initial finding

The supplied singleplayer trace (`C:/Users/hjelm/Downloads/singleplayer_smoothness_1791394165.json`) reports 820 same-tick pairs where ghost world X stayed fixed while its screen X moved backward by a median 2.104 px, then 280 new-tick pairs moving forward by 9.979 px median. This is consistent with a render-time mismatch: `main.gd` samples runner and camera using `Engine.get_physics_interpolation_fraction()`, while `GhostHazard.set_simulation_tick()` places the ghost at the integer simulation tick. In MP, `WorldSimulation.render_state()` already computes fractional presentation for several entities, but ghost state currently uses the integer world tick.

## Implementation plan

1. Keep authoritative ghost tick, phase, hitbox, contact, activation, and ledger state unchanged.
2. Give the shared ghost scene a presentation-only pose/phase sample. SP derives it from the same physics interpolation fraction as runner/camera; MP derives it from the existing delayed shared `presentation_tick` and world-history fraction.
3. Snap presentation on configure/activation/baseline or missing history; never interpolate across a discontinuous activation or lifecycle reset.
4. Add regressions for fractional motion and phase boundaries, then run bounded actual-scene captures at 240 Hz, 60 Hz, and uneven render deltas. Compare relative ghost/camera/runner movement and authoritative hitbox invariance.

## Implementation

- The shared `GhostHazard` node now has an explicit fractional presentation tick for moving variants. Its visual pose and warning/danger tint use this render sample; the hitbox and authoritative phase still use the integer simulation tick.
- SP feeds the node the same `simulation_tick - 1 + interpolation_fraction` sample used for the rendered runner and camera.
- MP adds that same fractional tick to the existing delayed `WorldSimulation.render_state(fraction)` result, and the shared scene consumes it. No client-local time or wall-clock prediction was introduced.
- Native Node2D physics interpolation is explicitly disabled for the ghost so Godot cannot interpolate the already-interpolated presentation pose a second time. On configure, activation, and snapshots without a fractional render sample, the scene snaps to the authoritative pose.
- The visible project build label is `2026.10.07-gen19-ghost-render-interpolation`; the Gen19 network/gameplay contract is unchanged.

## Verification

The focused headless scene regression passed on Godot 4.7.2: `GHOST_RENDER_INTERPOLATION failures=0 seed=100000030`. It checks the shared scene against analytic fractional positions, confirms presentation updates leave the authoritative hitbox unchanged, and exercises the SP adapter and MP render-state payload.

A separate non-headless OpenGL capture used the actual `main.tscn`, generated Gen19 seed `100000030`, its real selected pursuit ghost and SP camera/presentation pipeline. The fixture isolates this event on a stable flat support, starts beside its trigger, and performs a safe opposite-lane flip after 12 warning ticks so it can render through warning and danger without ending the run. At 60 Hz it captured 130 callbacks (median 60.1 Hz, one same-simulation-tick pair, relative screen displacement +1.1005 px); at 239.9 Hz it captured 530 callbacks (396 same-tick pairs, median relative screen displacement +0.9165 px, minimum +0.0643 px); the uneven-delta pass captured 131 callbacks (median 65.4 Hz). All three traversed warning and danger, had monotone presentation ticks and monotone dangerous-phase ghost/runner separation, and exited with zero capture failures. The capture also reports global physics interpolation disabled and the ghost node interpolation mode OFF.

Images and per-render callback JSON are in `gravity-run/.codex-ghost-render-review/gen19-ghost-{fps60,fps240,uneven}.{png,json}`. The original user trace had 820 same-tick ghost/runner screen pairs moving backward (median −2.104 px); the new 240 Hz runtime capture has 396 such pairs moving forward (median +0.9165 px, minimum +0.0643 px). This is a controlled singleplayer event fixture rather than a replay of the user’s full run. No actual networked MP browser capture was run; multiplayer integration is covered by the shared world render-state regression, not claimed as a live-match visual test.

Godot was launched only by bounded hidden test processes. Those processes exited; the pre-existing editor process (PID 53204) was left untouched. Headless Godot logs benign local `user://` log/shader-cache and certificate-store warnings in this environment; the test result itself was exit 0. No gameplay, API, generator, or migration change is intended. Existing unrelated working-tree edits (capture, menu, pacing, audio, and other reviews) remain outside this scope.
