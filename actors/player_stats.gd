extends RefCounted

# Stateless status calculations. Player retains its public properties and methods.
# Read live player/equipment state on every call; do not cache derived values.

static func _get_equipment_stats(player) -> Dictionary:
	if player.equipment_component and player.equipment_component.has_method("get_total_stats"):
		return player.equipment_component.get_total_stats()
	return {
		"attack": 0,
		"defense": 0,
		"max_hp": 0,
		"max_mp": 0,
		"strength": 0,
		"dexterity": 0,
		"intelligence": 0,
		"crit_bonus": 0.0,
		"hit_bonus": 0.0,
		"penetration_bonus": 0.0
	}

static func _get_hunger_attack_multiplier(player) -> float:
	var ratio = float(player.hunger) / max(1, player.max_hunger)
	if ratio >= 0.8:
		return 1.1
	elif ratio >= 0.5:
		return 1.0
	elif ratio >= 0.3:
		return 0.9
	else:
		return 0.8

static func _get_hunger_defense_multiplier(player) -> float:
	var ratio = float(player.hunger) / max(1, player.max_hunger)
	if ratio >= 0.8:
		return 1.05
	elif ratio >= 0.5:
		return 1.0
	elif ratio >= 0.3:
		return 0.95
	else:
		return 0.9

static func _get_warrior_instinct_multiplier(player) -> float:
	var st = player.get_battle_instinct_state()
	return 1.0 + float(st.get("bonus", 0.0))

static func get_battle_instinct_state(player) -> Dictionary:
	var gs = player.get_node_or_null("/root/GameState")
	if gs == null or gs.player_class != 1:
		return {"count": 0, "bonus": 0.0}
	var count = player._count_adjacent_hostiles()
	var capped = mini(count, 3)
	return {"count": count, "bonus": capped * 0.4}

static func get_raw_hit_rate(player) -> float:
	var equipment_stats = player._get_equipment_stats()
	var org_bonus = 0.0
	if player.equipment_component and player.equipment_component.equipment_data:
		org_bonus = float(player.get_inventory_bonus_state().get("hit_bonus", 0.0))
	return 0.85 + org_bonus + float(equipment_stats.get("hit_bonus", 0.0))

static func get_overflow_penetration_bonus(player) -> float:
	return maxf(0.0, player.get_raw_hit_rate() - 1.0) * 0.5

static func get_total_strength(player) -> int:
	var eq = player._get_equipment_stats()
	return player.strength + eq.strength

static func get_total_dexterity(player) -> int:
	var eq = player._get_equipment_stats()
	return player.dexterity + eq.dexterity

static func get_total_intelligence(player) -> int:
	var eq = player._get_equipment_stats()
	return player.intelligence + eq.intelligence

static func get_inventory_bonus_state(player) -> Dictionary:
	var cluster_count = player.equipment_component.equipment_data.get_cluster_count()
	var is_packed = player.equipment_component.equipment_data.is_tightly_packed()
	var density = player.equipment_component.equipment_data.get_packing_density()
	
	var result = {
		"state": "average",
		"message": "",
		"color": Color.WHITE,
		"crit_bonus": 0.0,
		"hit_bonus": 0.0
	}
	
	if cluster_count <= 1 and cluster_count > 0:
		if is_packed:
			# ◎ Excellent (Density 1.0)
			result.state = "perfect"
			result.message = " [◎完璧]: 会心+25% 命中+10%"
			result.color = Color(1.0, 0.84, 0.0) # Gold
			result.crit_bonus = 0.25
			result.hit_bonus = 0.1
		elif density >= 0.75:
			# 〇 Good (High Density)
			result.state = "good"
			result.message = " [〇良好]: 会心+15%"
			result.color = Color(0.3, 1.0, 0.3) # Green
			result.crit_bonus = 0.15
		else:
			# △ Average (Low Density, messy shape)
			result.state = "average"
			result.message = " [△整頓不足]: ボーナスなし"
			result.color = Color(0.8, 0.8, 0.8) # Gray
	elif cluster_count == 2:
		# △ Average (Split clusters)
		result.state = "average"
		result.message = " [△普通]: ボーナスなし"
		result.color = Color(0.8, 0.8, 0.8) # Gray
	elif cluster_count >= 3:
		# ✕ Bad
		result.state = "bad"
		result.message = " [✕散乱]: 命中-20%"
		result.color = Color(1.0, 0.3, 0.3) # Red
		result.hit_bonus = -0.2
		
	return result

static func get_attack_power(player) -> int:
	var equipment_stats = player._get_equipment_stats()
	# 攻撃力 = (力 * 2) + 装備の攻撃力
	var total_str = player.strength + equipment_stats.strength
	var base_value = (total_str * 2) + equipment_stats.attack 
	var mult = player._get_hunger_attack_multiplier() * player._get_warrior_instinct_multiplier()
	return int(round(base_value * mult))

static func get_defense_power(player) -> int:
	var equipment_stats = player._get_equipment_stats()
	# 防御力 = 装備の防御力 + 合計器用さの半分
	var total_dex = player.dexterity + equipment_stats.dexterity
	var base_value = equipment_stats.defense + (total_dex / 2)
	return int(round(base_value * player._get_hunger_defense_multiplier()))

static func get_crit_rate(player) -> float:
	# Base 5% + 1% per Dexterity point + Equipment Bonuses
	var base = 0.05
	var dex_bonus = float(player.dexterity) * 0.01

	var equipment_stats = player._get_equipment_stats()
	# Add equipment dexterity to bonus? Or is it already in 'dexterity'?
	# 'dexterity' is base stat. Equipment adds separately usually.
	# But wait, equipment_stats.dexterity is added to DEF above.
	# Let's add equipment dex to crit too.
	var equip_dex_bonus = float(equipment_stats.dexterity) * 0.01
	var item_crit_bonus = float(equipment_stats.get("crit_bonus", 0.0))

	# Inventory Adjacency Bonuses
	var adj_bonus = 0.0
	if player.equipment_component and player.equipment_component.bag_data:
		adj_bonus = player.equipment_component.bag_data.get_total_crit_bonus()

	var organization_bonus = 0.0
	if player.equipment_component and player.equipment_component.equipment_data:
		organization_bonus = float(player.get_inventory_bonus_state().get("crit_bonus", 0.0))

	# Grass Critical Bonus
	var grass_bonus = 0.0
	if player.is_in_grass and player._check_equipment_effect("crit_in_grass"):
		grass_bonus = 0.3 # +30% Crit in grass!

	var total = base + dex_bonus + equip_dex_bonus + item_crit_bonus + adj_bonus + organization_bonus + grass_bonus
	print("Crit Rate Debug - base:", base, "dex_bonus:", dex_bonus, "equip_dex_bonus:", equip_dex_bonus, "item_crit_bonus:", item_crit_bonus, "adj_bonus:", adj_bonus, "organization_bonus:", organization_bonus, "grass_bonus:", grass_bonus, "total:", total)
	return clamp(total, 0.0, 1.0)

static func get_penetration_rate(player) -> float:
	var equipment_stats = player._get_equipment_stats()
	var base_pen = clamp(float(equipment_stats.get("penetration_bonus", 0.0)), 0.0, 0.9)
	# 命中率の超過分(100%を超えた分)の半分を貫通率に加算する
	# 例: 命中110% → 超過10% → 貫通+5%
	var overflow = maxf(0.0, player.get_raw_hit_rate() - 1.0)
	return clamp(base_pen + overflow * 0.5, 0.0, 0.9)
