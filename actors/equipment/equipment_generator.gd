class_name EquipmentGenerator
extends RefCounted

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES = ["通常", "上質", "希少", "英雄", "伝説"]

const PREFIXES = [
	{"name": "鋭い", "attack": 2, "weight": 18},
	{"name": "堅牢な", "defense": 2, "weight": 18},
	{"name": "強靭な", "max_hp": 5, "weight": 14},
	{"name": "精密な", "effect": "hit_bonus", "value": 0.10, "weight": 12},
	{"name": "必殺の", "effect": "crit_bonus", "value": 0.10, "weight": 10},
	{"name": "貫通する", "effect": "penetration_bonus", "value": 0.15, "weight": 8},
	{"name": "炎を帯びた", "effect": "burn", "value": {
		"chance": 0.20, "min_duration": 2, "max_duration": 4, "damage": 1
	}, "weight": 8}
]

const SUFFIXES = [
	{"name": "力", "strength": 2, "weight": 18},
	{"name": "技", "dexterity": 2, "weight": 18},
	{"name": "知恵", "intelligence": 2, "weight": 18},
	{"name": "生命", "max_hp": 8, "weight": 14},
	{"name": "会心", "effect": "crit_bonus", "value": 0.08, "weight": 12},
	{"name": "必中", "effect": "hit_bonus", "value": 0.08, "weight": 10},
	{"name": "破砕", "effect": "penetration_bonus", "value": 0.10, "weight": 10}
]

static func enhance_item(base_item: BaseItem, level: int = 1) -> BaseItem:
	if not _is_equipment(base_item):
		var copy = base_item.duplicate(true) as BaseItem
		copy.ensure_connectors()
		return copy

	var item = base_item.duplicate(true) as BaseItem
	if item == null:
		return base_item

	var rng = RandomNumberGenerator.new()
	rng.randomize()
	item.generated_level = max(1, level)
	item.rarity = _roll_rarity(rng)
	item.id = "%s_generated_%d" % [base_item.id, rng.randi()]

	var affix_count = item.rarity
	if affix_count >= 1:
		_apply_affix(item, _pick_weighted(PREFIXES, rng), true, level)
	if affix_count >= 2:
		_apply_affix(item, _pick_weighted(SUFFIXES, rng), false, level)
	if affix_count >= 3:
		_apply_affix(item, _pick_weighted(PREFIXES, rng), true, level)
	if affix_count >= 4:
		_apply_affix(item, _pick_weighted(SUFFIXES, rng), false, level)

	var quality_scale = 1.0 + float(item.rarity) * 0.12
	item.attack = int(round(item.attack * quality_scale))
	item.defense = int(round(item.defense * quality_scale))
	item.value = max(item.value, 10) * (item.rarity + 1)
	_generate_connectors(item, rng)
	_rebuild_name_and_description(item, base_item.name)
	item.grid_position = Vector2i(-1, -1)
	return item

static func _generate_connectors(item: BaseItem, rng: RandomNumberGenerator):
	item.connectors.clear()
	if not item.is_equippable():
		return
	var colors = ["red", "blue", "yellow", "purple"]
	var preferred = "yellow"
	if item.attack > item.defense and item.attack > 0:
		preferred = "red"
	elif item.defense > item.attack and item.defense > 0:
		preferred = "blue"
	elif item.intelligence > 0 or item.max_mp > 0:
		preferred = "purple"
	var candidates: Array[Dictionary] = []
	for cell in item.shape:
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if not item.shape.has(cell + direction):
				candidates.append({"cell": cell, "direction": direction})
	candidates.shuffle()
	var connector_count = clamp(1 + int(item.rarity / 2), 1, 3)
	for i in range(min(connector_count, candidates.size())):
		var candidate = candidates[i]
		var color = preferred if i == 0 else colors[rng.randi_range(0, colors.size() - 1)]
		item.connectors.append({"cell": candidate.cell, "direction": candidate.direction, "color": color})

static func _is_equipment(item: BaseItem) -> bool:
	return item != null and item.is_equippable()

static func _roll_rarity(rng: RandomNumberGenerator) -> int:
	var roll = rng.randf()
	if roll < 0.02: return Rarity.LEGENDARY
	if roll < 0.08: return Rarity.EPIC
	if roll < 0.22: return Rarity.RARE
	if roll < 0.50: return Rarity.UNCOMMON
	return Rarity.COMMON

static func _pick_weighted(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total = 0
	for entry in pool:
		total += int(entry.get("weight", 1))
	var roll = rng.randi_range(1, max(1, total))
	for entry in pool:
		roll -= int(entry.get("weight", 1))
		if roll <= 0:
			return entry
	return pool[0]

static func _apply_affix(item: BaseItem, affix: Dictionary, is_prefix: bool, level: int):
	var scale = max(1, int(ceil(float(level) / 3.0)))
	for stat in ["attack", "defense", "max_hp", "max_mp", "strength", "dexterity", "intelligence"]:
		if affix.has(stat):
			item.set(stat, item.get(stat) + int(affix[stat]) * scale)
	if affix.has("effect"):
		var effect_id = str(affix.effect)
		var value = affix.value
		if value is Dictionary:
			item.effects[effect_id] = value.duplicate(true)
		else:
			item.effects[effect_id] = float(item.effects.get(effect_id, 0.0)) + float(value)
	if is_prefix:
		item.prefix_name = str(affix.name)
	else:
		item.suffix_name = str(affix.name)

static func _rebuild_name_and_description(item: BaseItem, base_name: String):
	var generated_name = base_name
	if item.prefix_name != "":
		generated_name = item.prefix_name + generated_name
	if item.suffix_name != "":
		generated_name += "・" + item.suffix_name
	item.name = generated_name
	item.description += "\n品質: %s" % RARITY_NAMES[item.rarity]
	
	# Add effect bonuses to description for debugging
	if item.effects.has("crit_bonus"):
		item.description += "\n会心率: +%.1f%%" % (float(item.effects["crit_bonus"]) * 100.0)
	if item.effects.has("hit_bonus"):
		item.description += "\n命中率: +%.1f%%" % (float(item.effects["hit_bonus"]) * 100.0)
	if item.effects.has("penetration_bonus"):
		item.description += "\n貫通率: +%.1f%%" % (float(item.effects["penetration_bonus"]) * 100.0)
