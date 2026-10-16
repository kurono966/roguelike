extends SceneTree

class Target extends Node2D:
	var hp = 100
	var enemy_name = "検証用の敵"
	var reaction = "stay"
	func take_damage(amount, _source = null, _elements = [], _critical = false):
		remove_from_group("enemies") # The test target has no NPC turn logic.
		hp -= amount
		if reaction == "die":
			hp = 0
			queue_free()
		elif reaction == "move": position += Vector2(32, 0)

var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func run_test():
	var main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	for entity in get_nodes_in_group("entities"):
		if entity != main.player: entity.queue_free()
	await process_frame
	main._is_on_world_map = false
	main.current_floor = 1
	for x in range(20, 31):
		for y in range(20, 31): main._map_data[x][y] = main.CellType.FLOOR
	main.player.equipment_component.equipment_data.clear()
	var item = ItemDatabase.get_item_by_id("rusty_sword")
	item.effects["hit_bonus"] = 10.0
	main.player.equipment_component.equipment_data.place_item(item, 0, 0)
	for reaction in ["stay", "die", "move"]:
		main.player.position = Vector2(25, 25) * 32
		main._current_game_state = main.TurnPhase.PLAYER_TURN
		main._auto_move_cooldown = 0
		var target = Target.new()
		target.reaction = reaction
		target.position = Vector2(26, 25) * 32
		main.add_child(target)
		target.add_to_group("entities")
		target.add_to_group("enemies")
		main._calculate_fov()
		main.request_move_to_tile(Vector2i(28, 25))
		var turn_before = main._turn_count
		await main._continue_path_following()
		check(main.player.position == Vector2(25, 25) * 32, "Attack advanced player: " + reaction)
		check(not main._is_path_following and main._current_path.is_empty() and not main._has_pending_path_target, "Attack left movement queued: " + reaction)
		check(main._turn_count == turn_before + 1 and main.player.last_action_id == "attack", "Attack lost turn: " + reaction)
		main._auto_move_cooldown = 0
		await main._continue_path_following()
		check(main.player.position == Vector2(25, 25) * 32, "Old click advanced after attack: " + reaction)
		if is_instance_valid(target): target.queue_free()
		await process_frame
	# A subsequent, explicit click must still allow movement.
	main._auto_move_cooldown = 0
	main.request_move_to_tile(Vector2i(26, 25))
	await main._continue_path_following()
	check(main.player.position == Vector2(26, 25) * 32, "New movement click stopped working")
	print("CLICK_ATTACK_STOP_TEST failures=", failures)
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
