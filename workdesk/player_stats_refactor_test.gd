extends SceneTree

class Hostile extends Node2D:
	var hp = 10

const BASELINE = "res://workdesk/player_stats_baseline.json"
var snapshots: Array = []

func _initialize():
	call_deferred("run_test")

func capture(player):
	snapshots.append([player.attack_power, player.defense_power, player.hit_rate,
		player.crit_rate, player.penetration_rate, player.get_raw_hit_rate(),
		player.get_overflow_penetration_bonus(), player.get_total_strength(),
		player.get_total_dexterity(), player.get_total_intelligence(),
		player._get_hunger_attack_multiplier(), player._get_hunger_defense_multiplier(),
		player.get_battle_instinct_state().count, player.get_battle_instinct_state().bonus,
		str(player.get_inventory_bonus_state())])

func run_test():
	var main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	var player = main.player
	var component = player.equipment_component
	component.equipment_data.clear()
	component.bag_data.clear()
	for group in ["enemies", "npcs", "allies"]:
		for actor in get_nodes_in_group(group): actor.remove_from_group(group)
	player.position = Vector2(25, 25) * 32
	var hostiles: Array = []
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1)]:
		var actor = Hostile.new()
		actor.position = player.position + Vector2(offset) * 32
		main.add_child(actor)
		hostiles.append(actor)
	for gear_mode in range(5):
		component.equipment_data.clear()
		for index in range(3 if gear_mode >= 3 else gear_mode):
			var item = BaseItem.new("stats_fixture", "装備", null, EquipmentSlot.EquipmentType.WEAPON)
			item.connectors_initialized = true
			item.attack = 3 + index
			item.defense = 2 + index
			item.strength = 2
			item.dexterity = 3
			item.intelligence = 4
			item.effects = {"crit_bonus": 0.12, "hit_bonus": 0.3, "penetration_bonus": 0.4, "crit_in_grass": true}
			component.equipment_data.place_item(item, index * 2 if gear_mode == 4 else index, 0)
		for hunger_value in [0, 29, 30, 49, 50, 79, 80, 100]:
			player.hunger = hunger_value
			for base_dex in [1, 3, 100]:
				player.dexterity = base_dex
				player.strength = base_dex
				player.intelligence = base_dex
				for grass in [false, true]:
					player.is_in_grass = grass
					for class_id in [0, 1]:
						root.get_node("GameState").player_class = class_id
						for count in [0, 1, 3, 5]:
							for index in range(hostiles.size()):
								if index < count: hostiles[index].add_to_group("enemies")
								else: hostiles[index].remove_from_group("enemies")
							capture(player)
	player.equipment_component = null
	# Equipment-free getters must still work before component initialization.
	snapshots.append([player.attack_power, player.defense_power, player.hit_rate, player.crit_rate,
		player.penetration_rate, player.get_total_strength(), player.get_total_dexterity(), player.get_total_intelligence()])
	player.equipment_component = component
	var actual = JSON.stringify(snapshots)
	var success = true
	if "--record" in OS.get_cmdline_user_args():
		var file = FileAccess.open(BASELINE, FileAccess.WRITE)
		file.store_string(JSON.stringify({"cases": snapshots.size(), "sha256": actual.sha256_text()}))
	else:
		var baseline = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
		success = snapshots.size() == baseline.cases and actual.sha256_text() == baseline.sha256
		if not success: push_error("Player status calculations changed from pre-refactor baseline")
	print("PLAYER_STATS_REFACTOR_TEST cases=", snapshots.size(), " failures=", 0 if success else 1)
	main.queue_free()
	await process_frame
	quit(0 if success else 1)
