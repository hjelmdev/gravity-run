extends Resource
class_name CharacterDefinition
## One playable runner: art, how it is drawn, its base stats and how it is
## unlocked. Add a character by adding a .tres of this type and listing it in
## CharacterCatalog. The collision box is shared by every character
## (RunnerMotion.SIZE) so courses and seeds stay fair; only art and stats vary.

@export var id: StringName = &"runner"
@export var display_name: String = "Runner"
@export_multiline var description: String = ""
## Short gameplay trait shown in the character picker ("" = none yet).
@export var trait_text: String = ""
@export var sprite_frames: SpriteFrames
## Integer scale keeps pixel art crisp: 32 px art at 2, 16 px art at 4.
@export var pixel_scale: float = 2.0
## Texture-space offset that puts the feet on the running surface. The sign is
## mirrored automatically when gravity flips.
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var stats: Resource
@export var unlocked_by_default: bool = true
## Price in coins once unlocking is wired to the account wallet (0 = free).
@export var unlock_cost_coins: int = 0
