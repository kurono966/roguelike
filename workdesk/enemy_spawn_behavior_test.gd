extends Node

class SpawnManager extends EnemyManager:
	var definition: Dictionary
	var spawn_grid = Vector2i(28, 25)
	func _get_random_enemy_data() -> Dictionary:
		return definition
	func _get_random_position_in_room(_room: Rect2i) -> Vector2i:
		return spawn_grid

class TestTurns extends TurnManager:
	func start_player_turn():
		pass

var failures = 0
var main
var spawner

func _ready():
	call_deferred("_run")

func _check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _spawn(id: String):
	spawner.definition = EnemyDatabase.get_enemy_def(id)
	spawner._spawn_enemy_in_room(Rect2i(20, 20, 15, 15))
	return get_tree().get_nodes_in_group("enemies").back()

func _run():
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	for group in ["enemies", "npcs", "allies", "items"]:
		for actor in get_tree().get_nodes_in_group(group):
			actor.queue_free()
	await get_tree().process_frame
	main._is_on_world_map = false
	main._traps.clear()
	main._burning_grass.clear()
	main.player.position = Vector2(25, 25) * 32
	main.player.max_hp = 10000
	main.player.hp = 10000
	main.player.equipment_component.equipment_data.items.clear()
	for x in range(20, 36):
		for y in range(20, 36):
			main._map_data[x][y] = main.CellType.FLOOR
	main._setup_pathfinding()
	spawner = SpawnManager.new()
	main.add_child(spawner)
	spawner.setup(main)
	var turns = TestTurns.new()
	main.add_child(turns)
	turns.setup(main)
	# Use the real room-spawn implementation, without manually assigning skills.
	var flame = _spawn("flame_scatterer")
	_check(flame.skill_id == "flame_scatter" and flame.attack_range == 4, "Room spawn lost flame skill/range")
	_check(flame.attack_power == 3 and flame.defense == 2 and flame.ai_type == 5, "Room spawn lost stats/AI")
	var hp_before = main.player.hp
	await turns.process_enemy_turns()
	_check(main.player.hp < hp_before and main.player.has_status_effect("burn"), "Spawned flame did not shoot fireball")
	main.player.status_effects.clear()
	main._map_data[28][26] = main.CellType.GRASS
	flame.skill_cooldown = 0
	await turns.process_enemy_turns()
	_check(main._burning_grass.has(Vector2i(28, 26)), "Spawned flame did not scatter fire")
	flame.queue_free()
	await get_tree().process_frame
	main._steam_tiles.clear()
	main._burning_grass.clear()
	main._map_data[28][26] = main.CellType.FLOOR
	spawner.spawn_grid = Vector2i(26, 25)
	var mushroom = _spawn("poison_mushroom")
	_check(mushroom.on_hit_effects.has("paralyze"), "Room spawn lost mushroom paralysis")
	# Keep the real 40% proc chance and exercise repeated hits with a fixed seed.
	seed(12345)
	mushroom.hit_rate = 1.0
	var paralyzed = false
	for attempt in range(20):
		await turns.process_enemy_turns()
		if main.player.has_status_effect("paralysis"):
			paralyzed = true
			break
	_check(paralyzed, "Spawned mushroom attacks never applied paralysis")
	main.player.status_effects.clear()
	mushroom.queue_free()
	await get_tree().process_frame
	# Old saves may contain empty skills produced by the broken spawn path.
	main._deserialize_enemy({"enemy_id": "flame_scatterer", "skill_id": "", "attack_range": 1, "hp": 9, "skill_cooldown": 2})
	var restored = get_tree().get_nodes_in_group("enemies").back()
	_check(restored.skill_id == "flame_scatter" and restored.attack_range == 4, "Old save did not recover static skills")
	_check(restored.hp == 9 and restored.skill_cooldown == 2, "Save recovery changed dynamic state")
	main._deserialize_enemy({"enemy_id": "poison_mushroom", "hp": 10})
	var restored_mushroom = get_tree().get_nodes_in_group("enemies").back()
	_check(restored_mushroom.on_hit_effects.has("paralyze"), "Saved mushroom lost its on-hit ability")
	# Verify all loaded species through the same room-spawn path.
	for id in EnemyDatabase._get_enemy_map():
		var data = EnemyDatabase.get_enemy_def(id)
		var actor = _spawn(id)
		_check(actor.attack_power == data.atk and actor.defense == data.get("def", 0), "Stats lost for " + id)
		_check(actor.skill_id == data.get("skill", "") and actor.on_hit_effects == data.get("on_hit", {}), "Abilities lost for " + id)
		_check(actor.attack_range == maxi(1, data.get("range", 1)) and actor.max_skill_cooldown == data.get("cooldown", 5), "Skill settings lost for " + id)
		actor.queue_free()
	print("ENEMY_SPAWN_BEHAVIOR_TEST failures=", failures)
	await get_tree().create_timer(2.1).timeout
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
