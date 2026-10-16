extends SceneTree

var failures = 0

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func run_test():
	var log_ui = root.get_node("LogUI")
	log_ui.log_history.clear()
	log_ui.add_log("重要な結果", Color.WHITE)
	log_ui.add_log("MP回復 +1", Color.BLUE)
	log_ui.add_log("重要な結果2", Color.WHITE)
	log_ui.add_log("重要な結果2", Color.WHITE)
	check(log_ui.log_history.size() == 3 and log_ui.log_history.back().count == 2, "Duplicate logs not consolidated")
	check(not log_ui.log_rich_label.get_parsed_text().contains("MP回復"), "Routine recovery clutters normal log")
	log_ui.toggle_visibility()
	check(log_ui.log_panel.visible and log_ui.log_rich_label.get_parsed_text().contains("MP回復"), "Expanded history lost details")
	check(log_ui.log_rich_label.get_parsed_text().find("重要な結果") < log_ui.log_rich_label.get_parsed_text().find("MP回復"), "Chronological order changed")
	log_ui.toggle_visibility()
	check(not log_ui.log_panel.visible, "Hidden mode broken")
	log_ui.add_log("非表示中の記録")
	log_ui.toggle_visibility()
	check(log_ui.log_panel.visible and log_ui.log_rich_label.get_parsed_text().contains("非表示中の記録"), "Hidden logs were lost")
	var main = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main._is_on_world_map = false
	main.player.exp_to_next_level = 100000
	main.player.hit_rate = 1.0
	var victim = load("res://actors/enemy/enemy.tscn").instantiate()
	victim.apply_definition(EnemyDatabase.get_enemy_def("zakomushi"))
	victim.hp = 1
	victim.loot_table.clear()
	victim.position = main.player.position + Vector2(32, 0)
	main.add_child(victim)
	await process_frame
	await process_frame
	main.player.hit_rate = 1.0
	log_ui.log_history.clear()
	await main.combat_manager.handle_attack(main.player, victim)
	var messages = []
	for entry in log_ui.log_history: messages.append(entry.raw)
	var damage_index = -1
	var death_index = -1
	var exp_index = -1
	for index in range(messages.size()):
		if messages[index].contains("→"): damage_index = index
		if messages[index].contains("を倒した"): death_index = index
		if messages[index].contains("EXP獲得"): exp_index = index
	check(damage_index >= 0 and death_index > damage_index and exp_index > death_index, "Combat results do not precede death and rewards")
	check(log_ui.log_rich_label.get_parsed_text().contains("T"), "Turn marker missing")
	log_ui.toggle_visibility()
	for index in range(80): log_ui.add_log("履歴 %d" % index)
	await process_frame
	await process_frame
	var scroll = log_ui.log_rich_label.get_v_scroll_bar()
	scroll.value = 20
	var scroll_before = scroll.value
	log_ui.add_log("閲覧中に新しいログ")
	await process_frame
	await process_frame
	check(is_equal_approx(scroll.value, scroll_before), "Reading old logs jumps to latest entry")
	print("LOG_CLEANUP_TEST failures=", failures)
	quit(1 if failures else 0)
