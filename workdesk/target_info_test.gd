extends SceneTree

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
	for group in ["enemies", "npcs", "allies", "items"]:
		for actor in get_nodes_in_group(group): actor.queue_free()
	await process_frame
	main._is_on_world_map = false
	main.player.position = Vector2(25, 25) * 32
	main._steam_tiles.clear()
	for x in range(20, 36):
		for y in range(20, 36):
			main._map_data[x][y] = main.CellType.FLOOR
	main._calculate_fov()
	var enemy = load("res://actors/enemy/enemy.tscn").instantiate()
	enemy.apply_definition(EnemyDatabase.get_enemy_def("root_eater"))
	enemy.position = Vector2(27, 25) * 32
	enemy.add_to_group("enemies")
	enemy.add_to_group("entities")
	main.add_child(enemy)
	var tm = main.target_manager
	var ui = root.get_node("GameUI")
	tm.start_look_targeting(main.player.position)
	var inspected_title = ui.tooltip_title_label.text
	var inspected_body = ui.tooltip_body_label.text
	check(inspected_title.contains("根食い") and inspected_body.contains("HP:"), "Look mode missing test target")
	tm.cancel_targeting()
	var weapon = ItemDatabase.get_item_by_id("wooden_bow")
	main.start_ranged_attack(weapon)
	check(ui.tooltip_panel.visible and ui.tooltip_title_label.text == inspected_title, "Ranged auto-target did not immediately show inspected enemy")
	check(ui.tooltip_body_label.text.begins_with(inspected_body), "Ranged tooltip differs from X information")
	check(ui.tooltip_body_label.text.contains("射程内") and tm.range_label.visible, "In-range feedback missing")
	enemy.position = Vector2(32, 25) * 32
	tm.update_cursor_mouse(enemy.position + Vector2(16, 16))
	check(ui.tooltip_title_label.text == inspected_title and ui.tooltip_body_label.text.contains("射程外"), "Out-of-range target lost its enemy information")
	enemy.position = Vector2(27, 25) * 32
	tm.keyboard_target_grid = Vector2i(25 + tm.targeting_range, 25)
	tm._update_visuals()
	check(not tm.is_target_out_of_range(), "Exact range boundary shown as out of range")
	tm.move_cursor(Vector2i.RIGHT)
	check(tm.is_target_out_of_range() and tm.range_label.text.contains("射程外"), "Keyboard range warning missing")
	check(ui.tooltip_body_label.text.contains("届きません"), "Tooltip lacks range warning")
	check(tm.path_line.default_color.r > tm.path_line.default_color.g, "Out-of-range line is not highlighted")
	tm.update_cursor_mouse(Vector2(27, 25) * 32 + Vector2(16, 16))
	check(ui.tooltip_title_label.text == inspected_title and not tm.is_target_out_of_range(), "Mouse target does not update information/range")
	tm.cancel_targeting()
	check(not tm.range_label.visible and not ui.tooltip_panel.visible and ui.tooltip_override_position == null, "Cancellation left stale information")
	tm.start_targeting(main.player.position, 1, null, {"id": "test", "range": 1}, false, 1, false)
	tm.update_cursor_mouse(enemy.position + Vector2(16, 16))
	check(tm.is_target_out_of_range() and tm.range_label.visible, "Point targeting lacks range warning")
	tm.cancel_targeting()
	main._visible_tiles[27][25] = false
	tm.start_targeting(main.player.position, 6, weapon, null, true, 0, true)
	tm.update_cursor_mouse(enemy.position + Vector2(16, 16))
	check(not ui.tooltip_title_label.text.contains("根食い"), "Hidden enemy information leaked")
	print("TARGET_INFO_TEST failures=", failures)
	quit(1 if failures else 0)
