# Ghost float and death sound

2026-10-04. Source gameplay commit `7c52576`; Pages commit `300e126841dff38719d647160666603a043824ed`.

- The shared GhostHazard scene draws a gentle cosmetic drift (3px horizontal, 5px vertical) and slight sway. Its node anchor, tick phases and collision rectangle remain fixed. Visible scenes animate at render cadence and reset their cosmetic phase when configured.
- Added original synthesized `assets/audio/sfx/death.wav`, 0.34 seconds, PCM16 mono 44.1kHz. The offline generator includes a rounded voiced vowel, dropping pitch and breath tail; it uses no third-party sampled sound. It can be replaced as a normal WAV asset.
- SP plays it from the normal death/end-run path, excluding menu demo. MP plays it only for the local runner, both for local simulation death and terminal confirmation. A round-scoped terminal-event ledger prevents repeated reports, render updates or unmute from replaying it; another player's death stays silent. Existing independent SFX mute/volume apply.
- No generator, protocol or database change. Visible application version is `2026.10.04-ghost-float-death-sfx`.

Verification: `ghost_float_death_sfx_test.tscn` PASS (actual MP callback, duplicate/remote/stale/muted deaths, fresh round, stationary hitbox despite visual movement). Actual `main.tscn` SP regression via `singleplayer_ghost_runtime_test.gd` PASS. Both pass again from the clean archive of exact commit `7c52576`. Web export succeeded with normal installed Godot template access. Previous unrelated capture/menu/pacing edits were preserved and excluded from the commit.

Build: `ghost-float-death-sfx-7c52576-20261004`. Pack: `index.ghost-float-death-sfx-7c52576-20261004.pck`, 3,090,592 bytes. SHA256 `4F362C337AFC62D1B9EE9947E69A88922049DB03518BD806CF58A6903A1BA7E3`.

Release verified: GitHub Pages workflow `37179299770` completed SUCCESS for Pages commit `300e126`. Fresh public pack download matches the clean export SHA256. Root opened the public root in IAB, confirmed the game iframe references this build and the real menu/demo renders; browser error/warning log was empty. This browser check does not constitute a played multiplayer death or a subjective listening review.

Test URL: https://hjelmdev.github.io/gravity-run/?build=ghost-float-death-sfx-7c52576-20261004
