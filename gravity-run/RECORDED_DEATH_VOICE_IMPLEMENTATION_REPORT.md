# Recorded death voice — selected proposal 3

Selected the unmodified CC0 `hurt_03.mp3` by EZduzziteh from the recorded voice preview page. Source, license and original SHA256 are recorded in `assets/audio/sfx/DEATH_SOUND_SOURCE.md`.

Both SP and MP use `SfxController.STREAMS.death`. The rejected synthetic WAV and its +8 dB boost have been removed. The recorded clip uses its original level with the shared SFX volume/mute settings. The offline synthetic preview generator no longer generates the rejected death asset.

Verification:
- Actual SP `_end_run()`/result-panel test passed with native WASAPI: playback advances after the result opens and a nonzero signal reaches the SFX bus. Fixture avoids progression writes.
- Local MP terminal callback/dedup/mute test passed (`ghost_float_death_sfx_test`).
- Tests and clean Web export use the committed source. Export log contains the imported MP3 and no export errors.
- Live game loads in browser with no captured errors/warnings. No subjective browser listening or actual MP race was performed.

Release:
- Azure source: `a0211e7`
- Visible version: `2026.10.04-recorded-death-3`
- Root build: `recorded-death-3-a0211e7-20261004`
- Pages commit: `4dabf4ed9baf9ca3f02ca7738280cb82c4673fc9`
- Pages workflow `37235612771` completed successfully for that exact SHA.
- Root/loader verified live; downloaded PCK matches clean export, 3,091,852 bytes.
- PCK SHA256: `3D82BC053D9EC1636C02A3968390730FEB5FFEDD272AE0668FC6755A706505BF`
- No API/generation/schema change or migration.

Test URL: https://hjelmdev.github.io/gravity-run/?build=recorded-death-3-a0211e7-20261004
