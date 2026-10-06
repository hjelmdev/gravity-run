# Opt-in Web right-edge diagnostic capture

User authorized 2026-10-06: capture the actual browser flicker as readable PNG frames rather than relying on video support or native fixture reproduction. Use existing Luna/root-review/release workflow.

## User flow

Add localized actions to the existing multiplayer diagnostics/menu: start a short right-edge capture, clear progress/completion indication, and save its package. Starting closes the overlay so it does not cover the gameplay capture; touches on the action must not flip the runner. Capture must keep working during real multiplayer play without pauses. Keep existing JSON diagnostics export intact. Save one ZIP containing numbered PNG strips and metadata JSON; no separate download per frame and no base64 images inserted into the normal 8MiB JSON report. No auto-upload.

## Shared bounded capture

Reusable capture/export component, with MP integration first; usable by SP without a second implementation. Off by default, no GPU reads or allocations until explicitly started. Use actual rendered game viewport at post-draw time, capturing only the right strip into retained images. At most one readback in flight, about one second at up to 30 samples/s, max 30 frames, explicit raw-image budget (e.g. 24MiB) and package budget. Discard each full-viewport readback immediately after crop. Respect viewport resolution/budget; stop cleanly and say why if capped or unsupported. Avoid serializing/compressing PNGs on every gameplay callback: encode/export after burst finishes, outside active capture. Avoid unlimited repeated capture histories; replace/clear prior capture explicitly and free buffers. Cancel/clean up on exit/new round/focus loss; completed package stays available until exported or replaced, as appropriate.

Sync each PNG with callback/frame index, actual post-draw time, viewport dimensions and strip rectangle, seed/generator/build/API, course/round phase, shared presentation tick, requested/applied camera-left and inverse canvas bounds, presentation clip-left/right, cave biome fragment/last ridge vertices when useful. Include readback/crop timing and frame intervals so collection-induced stalls cannot be mistaken for the original blink. Do not change normal presentation, gameplay or network timing. Clearly state capture overhead limitations; actual browser pixels are evidence, not assumed compositor proof.

## Verification and release

Meaningful tests: inactive zero-readback; one-in-flight; frame/byte limits; cancellation/restart/scene cleanup; PNG+metadata correspondence; ZIP readable with numbered valid PNG files; existing JSON export unchanged; HUD touches do not flip. Run actual Web export/browser download verification, not only native download-request message, and inspect the saved package. Native actual-scene tests supplement this. Bounded owned Godot/helper process cleanup.

Root reviews diff and actual package, Luna fixes findings; scoped Azure commit/push and clean exact-commit Web/Pages release. No database/API/generator migration for diagnostics-only scope. Verify workflow/head, both BUILD_ID/loaders and public PCK hash. Preserve unrelated dirty work, selected death audio and touch lifecycle. Report short user steps and expected download file.
