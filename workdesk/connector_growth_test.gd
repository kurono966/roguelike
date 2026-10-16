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
	var player = main.player
	var component = player.equipment_component
	component.equipment_data.clear()
	var colors = ["red", "blue", "yellow", "purple"]
	for row in range(4):
		player.connector_affinity[colors[row]] = row + 2
		for column in range(2):
			var item = BaseItem.new("test", "試験装備", null, EquipmentSlot.EquipmentType.WEAPON)
			item.shape.assign([Vector2i.ZERO])
			item.connectors.append({"cell": Vector2i.ZERO, "direction": Vector2i.RIGHT if column == 0 else Vector2i.LEFT, "color": colors[row]})
			component.equipment_data.place_item(item, column, row)
	var raw = component.get_connector_bonus()
	check(raw.total == 4 and raw.red == 1 and raw.purple == 1, "Affinity altered physical connection counts")
	var effects = component.get_connector_effects()
	check(effects.attack == 3 and effects.defense == 4, "Red/blue affinity not applied per connected edge")
	check(is_equal_approx(effects.hit_bonus, 0.07) and is_equal_approx(effects.crit_bonus, 0.08), "Yellow/purple affinity effects incorrect")
	var stats = component.get_total_stats()
	check(stats.attack == 3 and stats.defense == 4 and is_equal_approx(stats.hit_bonus, 0.07), "Affinity effects absent from actual stats")
	player._refresh_growth_stats()
	var hit_before = player.hit_rate
	player.pending_connector_choices = 1
	player.choose_connector_growth("yellow")
	check(is_equal_approx(player.hit_rate, hit_before + 0.01), "Yellow growth did not immediately update actual hit chance")
	component.equipment_data.clear()
	check(component.get_connector_effects().attack == 0, "Affinity grants equipment bonuses without connections")
	player.level = 20
	player.strength = 30
	player.dexterity = 30
	player.intelligence = 30
	player.base_known_skills.clear()
	for color in colors: player.connector_affinity[color] = 0
	player._check_skill_learning()
	check(not player.base_known_skills.has("fireball") and not player.base_known_skills.has("helm_splitter"), "Skills ignore required color values")
	player.pending_growth_choices = 1
	player.pending_connector_choices = 1
	player._show_growth_selection()
	check(not player.choose_connector_growth("red"), "Color could be selected before base stat")
	player.choose_level_growth("intelligence")
	check(player.is_connector_growth_turn() and paused, "Color choice did not retain pause")
	player.choose_connector_growth("purple")
	check(player.get_connector_affinity("purple") == 1 and player.base_known_skills.has("fireball"), "Color growth did not unlock eligible skill")
	check(not paused and not player.has_pending_growth_choices(), "Color choice did not complete level up")
	check(not player.choose_connector_growth("purple"), "Extra color growth allowed")
	main._deserialize_player(player, {"level": 4, "connector_affinity": {"red": 2, "blue": 3, "yellow": 4, "purple": 5}, "pending_growth_choices": 0, "pending_connector_choices": 1})
	check(player.get_connector_affinity("yellow") == 4 and player.is_connector_growth_turn(), "Save restore lost colors or second-stage choice")
	player._show_growth_selection()
	player.choose_connector_growth("red")
	check(player.get_connector_affinity("red") == 3 and not paused, "Restored color choice not usable")
	main._deserialize_player(player, {"level": 4})
	check(player.get_connector_affinity("red") == 0 and not player.has_pending_growth_choices(), "Legacy save defaults incorrect")
	check(player.get_skill_color_requirements_text().contains("赤"), "Skill color requirements not visible")
	print("CONNECTOR_GROWTH_TEST failures=", failures)
	quit(1 if failures else 0)
