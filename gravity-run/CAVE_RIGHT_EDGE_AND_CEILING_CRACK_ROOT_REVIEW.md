# Root review — ceiling crack and cave right-edge report

2026-10-06: crack visual source and actual MP landscape screenshot reviewed. Artwork is inset into solid terrain; lethal geometry remains in the unchanged model. Crack correction approved in principle for scoped visual release.

Cave report remains unresolved. Read `cave_match_right_edge_capture.gd`: it disables scene `_process`/physics and manually synchronizes camera.follow and presentation.set_camera_left. Its 1080 native rendered strips verify a deterministic scene fixture, not the autonomous MP shared-clock/Camera2D/draw scheduling path or Web browser. Therefore no-blink in that sequence does not exclude the user's symptom.

Requested a bounded actual process/shared-clock capture (preferably Web) comparing applied canvas transform and actual presentation clip-right per callback. Investigate whether camera/draw scheduling divergence exposes right-edge strips before changing the renderer. If not reproduced or unavailable, report that limitation explicitly; do not claim cave fixed. Luna owns the follow-up, no parallel implementation. Preserve gameplay/API/generator, unrelated dirty work and owned process cleanup.

## Release approval

Read the new `cave_match_live_process_capture.gd`: actual Match._process/camera/presentation/draw stays enabled; two injected local history poses and controlled coordinator clock advance the scene. Its native no-transport fixture does not reproduce the browser/network incident. Retain that explicit cave limitation; no cave renderer fix is claimed.

Root independently ran the geometry test: owned bounded Godot process exited 0, `CAVE_CRACK_GEOMETRY_TEST failures=0 lanes=floor,ceiling art=inset contact=unchanged`. Source, images and test evidence accepted. **APPROVED for scoped visual release of inset crack artwork and test/docs only.** No API/generator/database changes. Proceed Azure push, clean exact-commit Web/Pages publication; final acceptance requires workflow/head, loaders/build IDs and independent downloaded PCK hash verification.
