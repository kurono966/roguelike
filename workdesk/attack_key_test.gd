extends Node

var main
var enemy
var failures: int = 0

func _ready():
	call_deferred("_run")

func _check(condition: bool, message: String):
	if not condition:
		failures += 1
		push_error(message)

func _key(code: Key, echo: bool = false) -> InputEventKey:
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	return event

func _wait_for_control() -> bool:
	var deadline = Time.get_ticks_msec() + 2000
	while main._is_processing_action or main._current_game_state != main.TurnPhase.PLAYER_TURN:
		if Time.get_ticks_msec() >= deadline:
			return false
		await get_tree().create_timer(0.02).timeout
	return true

func _run():
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	for group in ["enemies", "npcs", "allies"]:
		for actor in get_tree().get_nodes_in_group(group):
			if is_instance_valid(actor) and not actor.is_queued_for_deletion():
				actor.queue_free()
	await get_tree().process_frame
	main.player.position = Vector2(25, 25) * 32
	main.player.hp = 500
	main.player.max_hp = 500
	main.player.hit_rate = 1.0
	main.player.status_effects.clear()
	# Remove equipment procs so attack/retaliation timing is deterministic.
	main.player.equipment_component.equipment_data.items.clear()
	main._traps.clear()
	for x in range(23, 29):
		for y in range(23, 29):
			main._map_data[x][y] = main.CellType.FLOOR
	main._setup_pathfinding()
	enemy = load("res://actors/enemy/enemy.tscn").instantiate()
	enemy.position = Vector2(26, 25) * 32
	enemy.hp = 500
	enemy.max_hp = 500
	enemy.hit_rate = 1.0
	enemy.attack_power = 1
	enemy.add_to_group("enemies")
	enemy.add_to_group("entities")
	main.add_child(enemy)
	main._calculate_fov()
	main.visibility_manager.update_entity_visibility()
	for key in [KEY_TAB, KEY_S]:
		for use_selected_target in [true, false]:
			main._current_target_enemy = enemy if use_selected_target else null
			var turn_before: int = main._turn_count
			var hp_before: int = enemy.hp
			main.input_handler._unhandled_input(_key(key))
			_check(main._is_processing_action, "Attack key failed to acquire action lock")
			_check(main._turn_count == turn_before, "Enemy turn began before player attack finished")
			# A second press or keyboard repeat must not start another attack/turn.
			main.input_handler._unhandled_input(_key(key))
			main.input_handler._unhandled_input(_key(key, true))
			var unlocked = await _wait_for_control()
			_check(unlocked, "Attack key left controls locked: %s" % key)
			if not unlocked:
				get_tree().quit(1)
				return
			_check(enemy.hp < hp_before, "Attack did not resolve")
			_check(main._turn_count == turn_before + 1, "Repeated key consumed multiple turns")
			# Damage recoil can legitimately outlive the turn; verify its final pose.
			await get_tree().create_timer(0.15).timeout
			_check(main.player.get_node("Sprite2D").position.is_equal_approx(Vector2(16, 16)), "Attack left sprite offset")
	# A miss and a lethal attack must both finish the turn as well.
	main.player.hit_rate = 0.0
	var hp_before_miss: int = enemy.hp
	main.input_handler._unhandled_input(_key(KEY_TAB))
	_check(await _wait_for_control(), "Miss left controls locked")
	_check(enemy.hp == hp_before_miss, "Guaranteed miss damaged enemy")
	main.player.hit_rate = 1.0
	enemy.hp = 1
	main.input_handler._unhandled_input(_key(KEY_S))
	_check(await _wait_for_control(), "Lethal attack left controls locked")
	# With no adjacent enemy these keys still wait exactly one turn and unlock.
	if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
		enemy.queue_free()
	await get_tree().process_frame
	main._current_target_enemy = null
	for key in [KEY_TAB, KEY_S]:
		var turn_before: int = main._turn_count
		main.input_handler._unhandled_input(_key(key))
		_check(await _wait_for_control(), "Wait key left controls locked")
		_check(main._turn_count == turn_before + 1, "Wait key did not consume exactly one turn")
		main.input_handler._unhandled_input(_key(key, true))
		_check(main._turn_count == turn_before + 1, "Keyboard repeat consumed a wait turn")
	var position_before: Vector2 = main.player.position
	Input.action_press("ui_down")
	main.input_handler._unhandled_input(_key(KEY_DOWN))
	Input.action_release("ui_down")
	_check(await _wait_for_control(), "Movement after attack left controls locked")
	_check(main.player.position == position_before + Vector2(0, 32), "Could not move after attack/wait")
	print("ATTACK_KEY_TEST: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
