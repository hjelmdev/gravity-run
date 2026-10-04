# Death SFX audibility and result transition

## Finding
The real singleplayer `_end_run()` path starts the death effect before showing the result panel. A native WASAPI fixture observed advancing playback after the panel opened, an unpaused scene tree, and nonzero mixed audio on the SFX bus. The result transition did not cut off the effect in this reproduction. This does not establish why the user heard no effect in their browser.

The original synthesized ouff has low voiced frequencies and is quiet at the default SFX setting. This delivery increases only its voice gain by 8 dB. Other SFX and both user volume settings remain unchanged. Every pooled voice resets its gain for each event, so coin/flip sounds cannot inherit the death boost. SP and MP use the same controller and asset.

## Verification
- `death_result_audio_test.gd`: passed against the clean source archive with WASAPI and `--verify-audio-output`. Exercises the actual SP result panel; checks playback advancement, actual mixed SFX signal, death deduplication, and gain reset on the next coin sound. Suppresses progression writes in the fixture.
- `ghost_float_death_sfx_test.tscn`: passed, including local MP terminal callback, repeated reports, remote death silence and mute/no replay.
- `sfx_shared_pool_test.tscn`: passed after rerunning with profile write access. First sandbox run failed its persistence check due to denied profile writes.
- Clean Web export passed, with no export script errors.
- Live root loaded in the browser without captured error/warning messages. No subjective browser listening or actual multiplayer race was performed.

## Release
- Azure gameplay source: `c7b347d`
- Pages: `17f342906b486fa9cf23d62f1214acb8611fa728`
- Visible version: `2026.10.04-death-sfx-level`
- Root build: `death-sfx-level-c7b347d-20261004`
- Pages workflow `37181746666`: completed, success, exact Pages SHA.
- Root wrapper and game loader both reference the new build/package.
- Downloaded public PCK: 3,093,948 bytes, SHA256 `74B34E4745674CACF1978B3790471126B2AD4A5D44986742A759E67FA6D77770`, matching the clean export.
- No schema/API/generation version changes or database migration.

Test the audible result using https://hjelmdev.github.io/gravity-run/?build=death-sfx-level-c7b347d-20261004 . If it is still completely silent, capture the game mode and confirm the visible version and SFX enable/volume settings; do not assume the level adjustment has diagnosed a browser-specific playback fault.
