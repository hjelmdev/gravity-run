# Approved gravity flip tone

User approved the inline `gravity-flip-tonal-layer.wav` preview: “perfekt!! exakt så! den tar vi”.

Root copied the exact preview to the existing shared SP/MP asset `assets/audio/sfx/gravity_flip.wav`. SHA-256: `3E6A9AE636B4DA53BA625E49B79342D0A76726A40260F3929D94D65B06FBDFD5`. It is PCM16 mono 44,100 Hz, 12,348 frames, 0.28 seconds.

The original generator was first reconstructed and matched every sample of the former WAV. Only its simultaneous deterministic `0.3 * air` layer was removed. The tone's phase, envelope, length and original gain reference are retained. `tools/audio/generate_sfx_previews.py::flip` now produces the approved PCM exactly; root independently verified byte-for-byte equality without regenerating other sound assets.

ROOT_APPROVED scope: this WAV and its generator function, exact-commit import/SFX check/Web export, Azure and Pages release. No gameplay, routing, volume settings, death audio, generator/API version or database changes. Preserve all unrelated uncommitted work. This is the user's selected sound replacement, not a fix for unverified mobile audio latency/stalls/coin behavior.

Publication verification pending.
