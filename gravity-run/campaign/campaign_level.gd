extends Resource
class_name CampaignLevel
## One fixed campaign stage. A stage is always the same course: a permanent
## seed, a pinned generator version and a ruleset whose biome is locked. The
## course ends at a finish line after length_px. Gravity stars are placed at
## fixed world positions (chosen by tools/campaign/campaign_level_tool.gd from
## the stage's own safe coin positions, then frozen here).

const CourseRunDefinitionScript := preload("res://systems/course_run_definition.gd")
## Where SP course distance 0 sits in world space (main.gd PLAYER_X).
const COURSE_START_X := 180.0
## No new hazards spawn in the last stretch before the finish line, so the
## runner always gets a calm, readable approach to the flag.
const FINISH_CALM_DISTANCE := 1200.0

@export var level_id: StringName = &"1-1"
@export var world_id: StringName = &"meadow"
## 1-based position inside its world (the boss is the last entry).
@export var index_in_world := 1
## English source strings; the UI passes them through tr().
@export var title := ""
@export var intro := ""
@export var seed_value := 1
@export var generator_version := 21
@export var ruleset: Resource
@export var length_px := 45000.0
## World-space positions (x includes COURSE_START_X).
@export var stars := PackedVector2Array()
## Hazard profile ids introduced on this stage; the first one seen shows a
## short "New:" callout.
@export var new_hazards := PackedStringArray()
## Biome the stage is drawn with. Empty means the ruleset's locked biome. The
## meadow look is presentation only; its encounters are generated as classic.
@export var presentation_biome: StringName = &""
## Non-empty for a scripted boss stage (no generated hazards).
@export var boss_id: StringName = &""

func is_boss() -> bool:
	return boss_id != StringName()

func get_finish_world_x() -> float:
	return COURSE_START_X + length_px

## Course distance after which generated encounters are no longer spawned.
func get_hazard_cutoff_distance() -> float:
	return length_px - FINISH_CALM_DISTANCE

func create_run_definition() -> Resource:
	var definition := CourseRunDefinitionScript.new() as Resource
	definition.set("scenario_id", &"campaign")
	definition.set("seed_value", seed_value)
	definition.set("generator_version", generator_version)
	definition.set("ruleset", ruleset)
	return definition

func get_presentation_biome() -> StringName:
	return presentation_biome if presentation_biome != StringName() else get_locked_biome()

func get_locked_biome() -> StringName:
	if ruleset == null:
		return &""
	return StringName(str(ruleset.get("locked_biome")))

## Stable identity for saved progress and, later, per-stage leaderboards. A
## change to the course, its length or its stars gives a new identity.
func get_identity() -> String:
	var definition := create_run_definition()
	var star_parts: Array[String] = []
	for star in stars:
		star_parts.append("%.0f,%.0f" % [star.x, star.y])
	return "%s|%s|%d|%s|%s" % [level_id, str(definition.call("get_course_identity")), int(length_px), ";".join(star_parts), String(boss_id)]
