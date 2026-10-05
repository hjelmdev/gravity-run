# Gen12: gap recovery, multiplayer SFX and biome rendering

Baseline: gameplay `40b7c1d`, Pages metadata `18f7717`, build `biome-risk-gen12-40b7c1d-20261005`.

## Confirmed gap-motion defect

`HazardInteractionRules.advance_barrel` landed falling barrels whenever their current Y was below the next supported floor. Crossing a gap edge after falling below the floor therefore snapped the barrel upward. The shared fix requires a downward surface crossing: previous Y <= floor Y <= new Y. Both ordinary and spiked barrels use this rule in SP and MP.

Local fix is implemented, not committed or published. `tools/barrel_motion_test.gd` passes both variants: a barrel below the far edge keeps falling; a barrel above the surface still lands. However `tools/spiked_barrel_shared_simulation_test.tscn` now FAILS for seed `100000003`: the barrel falls away before reaching its paired block. The published test meeting relied on the upward snap. Do not weaken the regression test or publish the motion fix alone as a complete encounter fix.

Validate the generated barrel's supported travel corridor from actual activation through block impact. Provide a genuinely supported spiked-barrel/block meeting and keep the deliberate gap fall irreversible. If correcting generation changes seed content, introduce the required new generator/manifest/API release contract and backend gates; preserve Gen12/older seed output. Verify the new meeting in both modes with the corrected shared motion before committing or publishing.

## Missing published cave-render fix

The prior local cave triangulation correction remains dirty in `biomes/biome_renderer.gd` and is absent from `40b7c1d`. Thus review captures used a correction that the clean published export did not contain. Include this exact reviewed hunk in the next scoped source commit and verify the clean archive, rather than the dirty workspace. Render cave frames across camera distances and biome boundaries; reject invalid-polygon errors. This is a plausible flicker cause, not proof of the user's particular MP observation or of other biome behavior.

## Multiplayer sound timing

Do not treat all sounds as delayed host events. Accepted local flips already call SfxController immediately. Locally predicted coin animation already emits visual_collection_started and plays its sound. Falling-rock impact and ghost warning are connected to the local presentation scene's phase changes. Barrel destruction follows canonical destroyed state; barrel death enters pending_barrel and waits for host resolution.

Clarify which effect and biome the user observed before changing those paths. Add narrow timing evidence where necessary: visible/local event time, SFX request time, host confirmation time, and actual effect type. Synchronize presentation sounds with the same local visual event, retaining stable round/entity event keys so host confirmation, retry and baseline do not replay a sound. Keep authoritative wallet/world decisions unchanged. For locally predicted lethal barrel contact, define rejected-contact behavior before playing an irreversible death cue. Test delayed confirmation, retries, baseline and mute/unmute; verify no delayed sound queue.

## Test accessibility and release

SP accepts explicit seeds through the challenge-code flow: `GR12-100000003`. The normal start button has no seed field; prior handoff should have explained this.

Keep existing recorded death audio and unrelated dirty capture/menu files. Publish only after sound scope is resolved and relevant fixes pass. Use an exact clean source archive, Azure push and scoped Pages update; verify workflow, both BUILD_ID markers, root/loader and downloaded PCK hash. Motion/render-only fixes need no new schema, but the required encounter-generation correction may require a release-gate migration.
