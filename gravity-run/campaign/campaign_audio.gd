extends RefCounted
## Per-world audio of the campaign, keyed by presentation biome. Add a row here
## (and a track from tools/audio/) to give a new world its own music, runner
## beat-sync tempo and gravity-star sound.

const WORLD_AUDIO := {
	&"meadow": {
		"track": preload("res://assets/audio/music/meadow_summer.ogg"),
		## tools/audio/generate_meadow_music.py
		"bpm": 140.0,
		"star_sfx": "gravity_star",
	},
	&"cave_campaign": {
		"track": preload("res://assets/audio/music/cave_echoes.ogg"),
		## tools/audio/generate_cave_audio.py
		"bpm": 150.0,
		"star_sfx": "crystal_chime",
	},
	&"haunted_campaign": {
		"track": preload("res://assets/audio/music/haunted_hollow.ogg"),
		## tools/audio/generate_haunted_audio.py
		"bpm": 132.0,
		"star_sfx": "haunted_star",
	},
	&"volcano_campaign": {
		"track": preload("res://assets/audio/music/volcano_forge.wav"),
		## tools/audio/generate_volcano_audio.gd
		"bpm": 156.0,
		"star_sfx": "ember_star",
	},
}

## The stage's own music, or null (the normal round track).
static func track_for(presentation_biome: StringName) -> AudioStream:
	return WORLD_AUDIO.get(presentation_biome, {}).get("track", null) as AudioStream

## Tempo of the stage's track in BPM, or 0.0 without a world track.
static func bpm_for(presentation_biome: StringName) -> float:
	return float(WORLD_AUDIO.get(presentation_biome, {}).get("bpm", 0.0))

static func star_sfx_for(presentation_biome: StringName) -> String:
	return str(WORLD_AUDIO.get(presentation_biome, {}).get("star_sfx", "gravity_star"))
