# Shared gameplay visual and audio follow-up

Date: 2026-10-02. This report covers the focused follow-up after the coin-provider transport release.

The falling-rock warning now uses one shared vector-drawn falling-stones triangle in single-player and multiplayer. Offscreen presentation places a forward marker at the viewport edge; the same warning state remains available through a translated accessible name and tooltip. The impact draws subtle ground cracks and spawns four short-lived decorative chips once. Chips have no collision or gameplay effect, and the rock keeps its existing buried collision shape.

Generator v8 delays the rock schedule to a 1,600 px activation lead, 104 warning ticks and 42 fall ticks. The longer shared warning preserves reaction margin while moving the visible fall later. Versioned v6 and v7 generation rules remain unchanged; multiplayer uses the v8 ruleset revision and game protocol `.4` so old clients cannot join with incompatible rules. No database migration was needed: the backend accepts the positive version and immutable registered manifest. The ordinary challenge `GR8-100000000` places the first rock at about 2,000 px.

Pause/resume now remembers the music cursor and restarts a stream at that cursor if a suspended browser backend stopped it. The resume path does not create a new round identity. Music OFF still stops playback and suppresses restart.

## Verification

- Godot 4.7.2: music controller; rock warning symbol and viewport layouts; warning route timing with 0.84 s initial cooldown plus 200 ms reaction; one-time collision-free impact chips; frozen v6/v7 manifest compatibility; v8 MP host/guest tick parity; v8 SP runtime; and 200-seed v8 distribution all passed.
- Distribution over seeds `100000000–100000199`, each 45,000 px: 843 accepted rocks (mean 4.215; 191/200 courses contain one or more) and 3,956 spike groups (mean 19.780). The generator is measurably more frequent while accepted rocks remain fewer than spike groups. Safety filters can still leave individual courses without a rock.
- Pause/resume and OFF behavior were tested against the Godot audio player. Browser autoplay/audio-context behavior and audible output were not verified in this follow-up.
- Provider transport and the real local-WebRTC prepare/start integration tests passed in the preceding transport work. A live authenticated multiplayer account match was not run.

## Published artifacts

The transport fix was previously published as source commit `65bc07091bdd87da18331df9a68b2785261fb115` and Pages commit `dfa79e125f0bcc66171a73610630df19d7981174`. The visual/audio follow-up source and Pages commit IDs and workflow result are to be recorded after publication.

The public test root is [https://hjelmdev.github.io/gravity-run/](https://hjelmdev.github.io/gravity-run/). Suggested focused manual check: pause/resume music mid-track and verify OFF stays silent; start challenge `GR8-100000000` and inspect the warning, later fall, impact cracks/chips, and permanent buried rock. A two-client authenticated room is still needed to verify the complete live account/start flow.
