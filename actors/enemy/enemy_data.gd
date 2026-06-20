class_name EnemyData
extends Resource

@export var id: String
@export var name: String
@export var hp: int = 1
@export var attack: int = 1
@export var defense: int = 0
@export var color: Color = Color.WHITE
@export var can_swim: bool = false
@export_file("*.png") var sprite: String = ""
@export var exp: int = 0
@export var penetration: float = 0.0
@export var intelligence: int = 0
@export var skill: String = ""
@export var range: int = 0
@export var cooldown: int = 0
@export var ai: int = 0
@export var knockback: bool = false
@export var fire_immune: bool = false
@export var grass_ignition_chance: float = 0.0
@export var is_npc: bool = false
@export var loot: Dictionary = {}
@export var on_hit: Dictionary = {}
@export var trade_items: Array[Dictionary] = []
@export var weak: Array[String] = []
@export var resist: Array[String] = []

func to_definition() -> Dictionary:
	var definition = {
		"name": name,
		"hp": hp,
		"atk": attack,
		"def": defense,
		"color": color,
		"swim": can_swim,
		"exp": exp
	}
	if sprite != "": definition["sprite"] = sprite
	if penetration != 0.0: definition["penetration"] = penetration
	if intelligence != 0: definition["intelligence"] = intelligence
	if skill != "": definition["skill"] = skill
	if range != 0: definition["range"] = range
	if cooldown != 0: definition["cooldown"] = cooldown
	if ai != 0: definition["ai"] = ai
	if knockback: definition["knockback"] = true
	if fire_immune: definition["fire_immune"] = true
	if grass_ignition_chance != 0.0: definition["grass_ignition_chance"] = grass_ignition_chance
	if is_npc: definition["is_npc"] = true
	if not loot.is_empty(): definition["loot"] = loot.duplicate(true)
	if not on_hit.is_empty(): definition["on_hit"] = on_hit.duplicate(true)
	if not trade_items.is_empty(): definition["trade_items"] = trade_items.duplicate(true)
	if not weak.is_empty(): definition["weak"] = weak.duplicate()
	if not resist.is_empty(): definition["resist"] = resist.duplicate()
	return definition
