extends Control

@onready var stats_label = $Panel/VBoxContainer/StatsLabel
@onready var class_container = $Panel/VBoxContainer/ClassContainer
@onready var detailed_container = $Panel/VBoxContainer/DetailedContainer
@onready var name_edit = $Panel/VBoxContainer/DetailedContainer/NameEdit
@onready var swim_check = $Panel/VBoxContainer/DetailedContainer/SwimCheck
@onready var growth_option = $Panel/VBoxContainer/DetailedContainer/GrowthOption
@onready var skill_option = $Panel/VBoxContainer/DetailedContainer/SkillOption
@onready var str_value_label = $Panel/VBoxContainer/DetailedContainer/StatGrid/StrValue
@onready var dex_value_label = $Panel/VBoxContainer/DetailedContainer/StatGrid/DexValue
@onready var int_value_label = $Panel/VBoxContainer/DetailedContainer/StatGrid/IntValue
@onready var hp_value_label = $Panel/VBoxContainer/DetailedContainer/StatGrid/HpValue

const CUSTOM_MIN_STAT = 1
const CUSTOM_MAX_STAT = 6
const CUSTOM_STARTING_POINTS = 6

var is_detailed_mode: bool = false
var custom_str: int = 2
var custom_dex: int = 2
var custom_int: int = 2
var custom_hp_bonus: int = 1
var growth_ids: Array[String] = ["balanced", "power", "agility", "magic", "survival"]
var skill_ids: Array[String] = ["", "heal", "blank_shot", "fireball", "teleport", "freeze"]

func _ready():
	var gs = get_node_or_null("/root/GameState")
	is_detailed_mode = gs.detailed_character_creation if gs else false
	class_container.visible = not is_detailed_mode
	detailed_container.visible = is_detailed_mode
	
	if gs:
		if is_detailed_mode:
			name_edit.text = gs.player_name
			_setup_detail_options()
			_apply_custom_character()
		else:
			gs.set_class_stats(0)  # Default to Balanced
	_update_ui()
	if is_detailed_mode:
		name_edit.grab_focus()
	else:
		$Panel/VBoxContainer/ClassContainer/BtnBalanced.grab_focus()

func _on_class_selected(class_id: int):
	var gs = get_node("/root/GameState")
	if gs:
		gs.set_class_stats(class_id)
		_update_ui()
	else:
		printerr("GameState autoload not found!")

func _update_ui():
	var gs = get_node_or_null("/root/GameState")
	if not gs: return
	
	if is_detailed_mode:
		var remaining = _get_remaining_points()
		_update_detail_value_labels()
		var txt_custom = "[center][b]Custom Character[/b]\n\n"
		txt_custom += "Points Left: %d\n\n" % remaining
		txt_custom += "Strength: %d\n" % custom_str
		txt_custom += "Dexterity: %d\n" % custom_dex
		txt_custom += "Intelligence: %d\n" % custom_int
		txt_custom += "HP Bonus: %d\n" % custom_hp_bonus
		txt_custom += "Max HP: %d\n" % (10 + custom_hp_bonus + int(custom_str / 3))
		txt_custom += "Max MP: %d\n" % (5 + custom_int * 2)
		if swim_check.button_pressed:
			txt_custom += "[color=cyan]Ability: Swimming[/color]\n"
		txt_custom += "\nGrowth: %s\n" % _get_selected_growth_label()
		txt_custom += "Skill: %s\n" % _get_selected_skill_label()
		txt_custom += "\n%s" % _get_build_summary()
		txt_custom += "[/center]"
		stats_label.text = txt_custom
		return
	
	var txt = "[center][b]Class Attributes[/b]\n\n"
	txt += "Strength: %d\n" % gs.initial_str
	txt += "Dexterity: %d\n" % gs.initial_dex
	txt += "Intelligence: %d\n" % gs.initial_int
	
	if gs.initial_hp_bonus > 0:
		txt += "HP Bonus: +%d\n" % gs.initial_hp_bonus
	elif gs.initial_hp_bonus < 0:
		txt += "HP Penalty: %d\n" % gs.initial_hp_bonus
	else:
		txt += "HP Bonus: 0\n"
		
	if gs.initial_can_swim:
		txt += "[color=cyan]Ability: Swimming[/color]\n"
		
	if gs.player_class == 2: # Rogue
		txt += "[color=green]Ability: 草眼[/color]\n"
		
	if gs.player_class == 99:
		txt += "[color=magenta]Special: All Skills & God Stats[/color]\n"
		
	txt += "[/center]"
	stats_label.text = txt

func _get_spent_points() -> int:
	return (custom_str - CUSTOM_MIN_STAT) + (custom_dex - CUSTOM_MIN_STAT) + (custom_int - CUSTOM_MIN_STAT) + max(0, custom_hp_bonus)

func _get_remaining_points() -> int:
	var swim_cost = 1 if swim_check and swim_check.button_pressed else 0
	return CUSTOM_STARTING_POINTS - _get_spent_points() - swim_cost

func _can_increase_stat(stat_name: String) -> bool:
	if _get_remaining_points() <= 0:
		return false
	match stat_name:
		"str":
			return custom_str < CUSTOM_MAX_STAT
		"dex":
			return custom_dex < CUSTOM_MAX_STAT
		"int":
			return custom_int < CUSTOM_MAX_STAT
		"hp":
			return custom_hp_bonus < CUSTOM_MAX_STAT
	return false

func _on_adjust_stat(stat_name: String, amount: int):
	if amount > 0 and not _can_increase_stat(stat_name):
		return
	match stat_name:
		"str":
			custom_str = clamp(custom_str + amount, CUSTOM_MIN_STAT, CUSTOM_MAX_STAT)
		"dex":
			custom_dex = clamp(custom_dex + amount, CUSTOM_MIN_STAT, CUSTOM_MAX_STAT)
		"int":
			custom_int = clamp(custom_int + amount, CUSTOM_MIN_STAT, CUSTOM_MAX_STAT)
		"hp":
			custom_hp_bonus = clamp(custom_hp_bonus + amount, 0, CUSTOM_MAX_STAT)
	_apply_custom_character()
	_update_ui()

func _on_swim_toggled(button_pressed: bool):
	if button_pressed and _get_remaining_points() < 0:
		swim_check.button_pressed = false
		return
	_apply_custom_character()
	_update_ui()

func _on_name_changed(_new_text: String):
	_apply_custom_character()

func _setup_detail_options():
	if growth_option.item_count == 0:
		growth_option.add_item("Balanced Growth")
		growth_option.add_item("Power Growth")
		growth_option.add_item("Agility Growth")
		growth_option.add_item("Magic Growth")
		growth_option.add_item("Survival Growth")
	if skill_option.item_count == 0:
		skill_option.add_item("No starting skill")
		skill_option.add_item("Heal")
		skill_option.add_item("Blank Shot")
		skill_option.add_item("Fireball")
		skill_option.add_item("Teleport")
		skill_option.add_item("Freeze")

func _update_detail_value_labels():
	str_value_label.text = str(custom_str)
	dex_value_label.text = str(custom_dex)
	int_value_label.text = str(custom_int)
	hp_value_label.text = str(custom_hp_bonus)

func _get_selected_growth_id() -> String:
	return growth_ids[growth_option.selected] if growth_option and growth_option.selected >= 0 else "balanced"

func _get_selected_skill_id() -> String:
	return skill_ids[skill_option.selected] if skill_option and skill_option.selected >= 0 else ""

func _get_selected_growth_label() -> String:
	return growth_option.get_item_text(growth_option.selected) if growth_option and growth_option.selected >= 0 else "Balanced Growth"

func _get_selected_skill_label() -> String:
	return skill_option.get_item_text(skill_option.selected) if skill_option and skill_option.selected >= 0 else "No starting skill"

func _get_build_summary() -> String:
	if custom_str >= custom_dex and custom_str >= custom_int:
		return "Style: Melee damage and sturdy gear."
	if custom_dex >= custom_str and custom_dex >= custom_int:
		return "Style: Accuracy, crits, and evasive play."
	return "Style: MP scaling and skill damage."

func _on_growth_selected(_index: int):
	_apply_custom_character()
	_update_ui()

func _on_skill_selected(_index: int):
	_apply_custom_character()
	_update_ui()

func _apply_custom_character():
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.set_custom_character(
			name_edit.text if name_edit else "Hero",
			custom_str,
			custom_dex,
			custom_int,
			custom_hp_bonus,
			swim_check.button_pressed if swim_check else false,
			_get_selected_skill_id(),
			_get_selected_growth_id()
		)

func _on_start_button_pressed():
	if is_detailed_mode:
		_apply_custom_character()
	# Transition to the main game
	if get_tree():
		get_tree().change_scene_to_file("res://world/main.tscn")
