extends Node

var failures = 0
var main

func _ready():
	call_deferred("_run")

func _check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _transition(floor_number: int, upward: bool):
	var old_floor_epoch = main._floor_epoch
	var turn_before = main._turn_count
	var hp_before = main.player.hp
	# Simulate auto actions and a queued click left over from the old map.
	main._is_auto_moving = true
	main._is_resting = true
	main._is_auto_exploring = true
	main._is_path_following = true
	main._has_pending_path_target = true
	main._current_game_state = main.TurnPhase.ENEMY_TURN
	main._change_floor(floor_number, 0, upward)
	await main._end_player_turn(old_floor_epoch) # Old movement/skill completion must be discarded.
	_check(main._current_game_state == main.TurnPhase.PLAYER_TURN, "Arrival did not give player control")
	_check(not main._is_auto_moving and not main._is_resting and not main._is_auto_exploring and not main._is_path_following and not main._has_pending_path_target, "Old actions survived floor change")
	main._process(0.2)
	await get_tree().create_timer(0.25).timeout
	_check(main._turn_count == turn_before and main.player.hp == hp_before, "Arrival consumed a turn or allowed enemy damage")

func _run():
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	main.player.max_hp = 10000
	main.player.hp = 10000
	main.player.status_effects.clear()
	main.player.equipment_component.equipment_data.items.clear()
	main._is_on_world_map = false
	main.current_floor = 1
	main._current_branch = 0
	await _transition(2, false) # Newly generated floor.
	for group in ["enemies", "npcs", "allies"]:
		for actor in get_tree().get_nodes_in_group(group):
			actor.remove_from_group(group)
			actor.remove_from_group("entities")
			actor.queue_free()
	await get_tree().process_frame
	main._traps.clear()
	main._burning_grass.clear()
	main._steam_tiles.clear()
	main._frozen_tiles.clear()
	for x in range(main.MAP_WIDTH):
		for y in range(main.MAP_HEIGHT):
			if main._map_data[x][y] == main.CellType.STAIRS_UP:
				main._map_data[x][y] = main.CellType.FLOOR
	for x in range(23, 30):
		for y in range(23, 30):
			main._map_data[x][y] = main.CellType.FLOOR
	main._map_data[25][25] = main.CellType.STAIRS_UP
	main.player.position = Vector2(25, 25) * 32
	var archer = load("res://actors/enemy/enemy.tscn").instantiate()
	archer.apply_definition(EnemyDatabase.get_enemy_def("skeleton_archer"))
	archer.position = Vector2(27, 25) * 32
	archer.add_to_group("enemies")
	archer.add_to_group("entities")
	main.add_child(archer)
	await _transition(1, true) # Cached upstairs.
	await _transition(2, false) # Cached downstairs with enemy in firing range.
	var hp_before = main.player.hp
	var turn_before = main._turn_count
	await main._end_player_turn() # Player deliberately waits: enemy may now act.
	_check(main._turn_count == turn_before + 1 and main.player.hp < hp_before, "Enemy did not resume after player's first action")
	# Falling during movement still returns through the old input's turn-end path.
	main.player.position = Vector2(25, 25) * 32
	main._map_data[25][25] = main.CellType.FLOOR
	main._map_data[26][25] = main.CellType.PIT
	main._setup_pathfinding()
	main._pending_pit_warning_grid = Vector2i(26, 25)
	var fall_epoch = main._floor_epoch
	turn_before = main._turn_count
	hp_before = main.player.hp
	await main._try_move_character(main.player, Vector2.RIGHT)
	await main._end_player_turn(fall_epoch)
	_check(main._floor_epoch > fall_epoch and main.current_floor == 3, "Pit did not change floors")
	_check(main._turn_count == turn_before and main.player.hp == hp_before - 10, "Pit arrival allowed NPC turn or extra damage")
	# An in-flight enemy attack and its remaining NPC phase must also stop.
	for group in ["enemies", "npcs", "allies"]:
		for actor in get_tree().get_nodes_in_group(group):
			actor.remove_from_group(group)
			actor.remove_from_group("entities")
			actor.queue_free()
	await get_tree().process_frame
	main._traps.clear()
	main._burning_grass.clear()
	main._steam_tiles.clear()
	main._poison_gas_tiles.clear()
	for x in range(23, 30):
		for y in range(23, 30):
			main._map_data[x][y] = main.CellType.FLOOR
	main.player.position = Vector2(25, 25) * 32
	main._setup_pathfinding()
	var pending_archer = load("res://actors/enemy/enemy.tscn").instantiate()
	pending_archer.apply_definition(EnemyDatabase.get_enemy_def("skeleton_archer"))
	pending_archer.position = Vector2(27, 25) * 32
	pending_archer.add_to_group("enemies")
	pending_archer.add_to_group("entities")
	main.add_child(pending_archer)
	main.turn_manager.process_enemy_turns()
	main._change_floor(4, 0)
	main.player.position = Vector2(25, 25) * 32
	hp_before = main.player.hp
	var arrival_positions = {}
	for group in ["enemies", "npcs", "allies"]:
		for actor in get_tree().get_nodes_in_group(group):
			if not actor.is_queued_for_deletion(): arrival_positions[actor] = actor.position
	await get_tree().create_timer(0.6).timeout
	_check(main.player.hp == hp_before, "Old projectile damaged player after floor change")
	_check(main._current_game_state == main.TurnPhase.PLAYER_TURN, "Old enemy phase resumed after floor change")
	for actor in arrival_positions:
		_check(is_instance_valid(actor) and actor.position == arrival_positions[actor], "Arrival NPC acted during old turn")
	print("FLOOR_FIRST_TURN_TEST failures=", failures)
	await get_tree().create_timer(1.0).timeout
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
