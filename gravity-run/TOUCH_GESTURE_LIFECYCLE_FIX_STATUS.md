# Touch gesture lifecycle fix status

Updated 2026-10-05. **Phase: RELEASE_COMPLETE.**

## Baseline and findings

- Baseline is Gen13/API `2.1.20261005.9`, gameplay commit `5983a19`, public build `gen13-gap-safe-barrels-5983a19-20261005`.
- The reported match evidence shows no multi-second engine stall. Stale touch state is a concrete code weakness and plausible cause, but this incident has no touch event telemetry and the root cause is not confirmed.
- SP (`player/player.gd`) and MP (`multiplayer_v2_match.gd`) previously tracked swipe press/release independently in `_unhandled_input`. If a matching release was consumed by a GUI control, or the MP debug menu returned early, the active finger index could remain latched.

## Implementation ready for review

- Added shared `systems/touch_gesture_lifecycle.gd` for SP and MP. Presses still begin only after GUI dispatch in `_unhandled_input`. A matching release is observed first in `_input`, then consumed and evaluated in `_unhandled_input`; a deferred fallback cancels it if GUI consumed the release. This avoids clearing a valid swipe before it is evaluated.
- Menu/pause, application/window focus loss, tree pause, input disable, same-index reuse, and a five-second missing-lift timeout clear stale gesture state. Other fingers are ignored while an active gesture remains, preserving the original finger's legitimate gesture.
- Platform-canceled `InputEventScreenTouch` releases are handled explicitly in `_input` and ignored by swipe evaluation in `_unhandled_input`; cancellation is scoped to the active finger so an unrelated finger cannot cancel a legitimate gesture.
- Existing swipe distance/direction checks and tap/mouse/keyboard modes remain in place. Pause UI is explicitly excluded in SP; interactive MP controls consume GUI input before `_unhandled_input`.
- Added bounded diagnostics for gesture begin/end/cancel/rejection, input-blocked transitions, queued/accepted/rejected flips, and MP blocked-state transitions. No per-frame diagnostic records were added.
- Existing render-capture hunks in `main.gd`, capture/pacing files, `ui/main_menu.gd`, and selected `death.mp3` are unrelated and remain untouched/unstaged.

## Verification

- `tools/touch_gesture_lifecycle_test.tscn` passes with failures=0. It covers release consumed over GUI, deferred fallback vs normal release ordering, platform-canceled touches with large deltas in SP and MP and the next swipe after cancellation, immediately subsequent swipes, menu-open and focus-loss cancellation, missing-lift timeout, second finger, actual SP Player normal swipe/tap/keyboard, pause-control no-flip, cooldown rejection, disabled/blocked SP input, actual MP match queuing, menu cancellation, GUI-consumed release recovery, focus reset, and a blocked runner's valid shared RunnerMotion escape flip. It also checks SP diagnostic lifecycle and flip outcome events.
- The same scene uses `Viewport.push_input` against real menu and volume Buttons while both a SP Player and MP match are present. A game-area press starts both gestures; release over the menu leaves SP gravity unchanged, queues no MP flip, and clears both gestures. Touch sequences begun on the actual menu/volume controls reach their GUI handlers and do not flip/queue gravity.
- The exact source commit was archived to `E:/Utveckling/Gravity Run/.codex-touch-release-838376b`; the clean archive imported successfully and the lifecycle scene passed there with failures=0, exit=0. Test runs were bounded to 45 seconds and only the user's editor process (PID 53204) remained afterward.
- Godot reports known sandbox log/certificate warnings and dummy-renderer RID/ObjectDB cleanup warnings on test exit; the test itself reports failures=0.

## Release verification

- Azure source commit `838376b48beccf6d00f123cce5b946192e7c501f` (`Fix touch gesture cancellation and GUI dispatch`) was pushed to `codex/current-prototype` at the verified Azure origin.
- The clean Web export was built from that exact commit archive. PCK size: 3,165,700 bytes; SHA-256: `F6DCA033CC108FD523180C3C7F8ED6ADF31FCC6FF5BEBB025135F19FDEA4F056`.
- Pages commit `51a402cc25195cd7d3da0fc0336bd87d9fa788f0` (`Deploy touch gesture lifecycle fix`) was pushed to `main` at `https://github.com/hjelmdev/gravity-run`. Workflow `37327579974` completed successfully for that commit.
- Public root loader, `docs/BUILD_ID`, and `docs/game/BUILD_ID` report `touch-gesture-lifecycle-gen13-838376b-20261005`. The loader references the versioned PCK. Its public download is 3,165,700 bytes with the same SHA-256 as the clean local export.
- Public game: https://hjelmdev.github.io/gravity-run/

## Limits

- This hardens stale/canceled touch handling but does not prove touch handling caused the previously reported round freeze. The available match evidence showed no multi-second engine stall, and there is no authenticated reproduction or incident touch log; the incident cause remains a hypothesis.
- No gameplay, network, frame-pacing, audio, backend migration, or network-version gate changes are included.
