extends SceneTree

class TestTurns extends TurnManager:
	var enemy_phases = 0
	func process_enemy_turns():
		enemy_phases += 1

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
	var player = main.player
	var str_before = player.strength
	var dex_before = player.dexterity
	var int_before = player.intelligence
	var hp_before = player.level_hp_bonus
	var mp_before = player.level_mp_bonus
	player.level = 1
	player.exp = 0
	player.exp_to_next_level = 10
	player.gain_exp(25)
	check(player.level == 3 and player.pending_growth_choices == 2, "Multiple levels did not queue one choice each")
	check(player.strength == str_before and player.dexterity == dex_before and player.intelligence == int_before, "Class still grants automatic stats")
	check(player.level_hp_bonus == hp_before and player.level_mp_bonus == mp_before, "HP/MP still grow automatically")
	await process_frame
	check(paused and is_instance_valid(player._growth_selection), "Growth selection did not pause game")
	check(player.is_level_up_sound_playing() and not player._growth_selection.content.visible, "Choices appeared before level-up sound finished")
	check(not player.choose_level_growth("strength") and not player.choose_connector_growth("red"), "Growth accepted input during level-up sound")
	var blocked_key = InputEventKey.new()
	blocked_key.keycode = KEY_1
	blocked_key.pressed = true
	player._growth_selection._unhandled_key_input(blocked_key)
	check(player.pending_growth_choices == 2, "Key input consumed growth during sound")
	while player.is_level_up_sound_playing():
		await player.level_up_audio_finished
	check(player._growth_selection.content.visible and paused, "Choices did not appear after audio completion")
	check(player._growth_selection.buttons.size() == 3, "Missing growth options")
	var turns = TestTurns.new()
	main.add_child(turns)
	turns.setup(main)
	turns.end_player_turn()
	check(turns.enemy_phases == 0, "Enemy phase started before growth selection")
	check(not player.choose_level_growth("hp") and not player.choose_level_growth("mp"), "Removed HP/MP options still accepted")
	check(not player.choose_level_growth("invalid") and player.pending_growth_choices == 2, "Invalid selection consumed a choice")
	player._growth_selection.buttons[0].pressed.emit()
	check(player.strength == str_before + 1 and player.pending_growth_choices == 1 and paused, "Strength selection or multi-level modal failed")
	check(player._growth_selection.buttons.size() == 4 and player.is_connector_growth_turn(), "Basic choice did not advance to four colors")
	player._growth_selection.buttons[3].pressed.emit()
	player._growth_selection.buttons[1].pressed.emit()
	player._growth_selection.buttons[0].pressed.emit()
	check(player.dexterity == dex_before + 1 and player.pending_growth_choices == 0, "DEX selection failed")
	check(not paused and player._growth_selection == null, "Game remained paused after selection")
	await process_frame
	check(turns.enemy_phases == 1, "Turn did not resume exactly once")
	check(not player.choose_level_growth("strength"), "Extra growth could be selected without level up")
	player.pending_growth_choices = 2
	player.pending_connector_choices = 2
	player._show_growth_selection()
	player.choose_level_growth("dexterity")
	player.choose_connector_growth("yellow")
	player.choose_level_growth("intelligence")
	player.choose_connector_growth("blue")
	check(player.dexterity == dex_before + 2 and player.intelligence == int_before + 1, "DEX/INT growth failed")
	check(player.level_mp_bonus == mp_before and player.hp == player.max_hp and player.mp == player.max_mp, "MP selection or restoration failed")
	check(not paused, "Last selection did not release pause")
	# Existing saves default to no pending choices; newer saves can restore them.
	main._deserialize_player(player, {"level": 4, "strength": 8, "dexterity": 7, "intelligence": 6, "pending_growth_choices": 1})
	check(player.strength == 8 and player.pending_growth_choices == 1, "Save restore lost existing stats or unspent choice")
	player._show_growth_selection()
	player.choose_level_growth("strength")
	player.choose_connector_growth("purple")
	check(player.pending_growth_choices == 0 and not paused, "Restored choice could not be spent")
	main._deserialize_player(player, {"level": 4, "strength": 8})
	check(player.strength == 8 and player.pending_growth_choices == 0, "Legacy save gained retroactive choices")
	print("LEVEL_GROWTH_TEST failures=", failures)
	quit(1 if failures else 0)
