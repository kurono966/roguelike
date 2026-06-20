extends Node

var player_name: String = "Hero"
# 0: Balanced, 1: Warrior, 2: Rogue, 3: Mage
var player_class: int = 0 
var detailed_character_creation: bool = false
var custom_growth_rates: Dictionary = {"str": 0.5, "dex": 0.5, "int": 0.5, "hp": 2.0}

var initial_str: int = 1
var initial_dex: int = 1
var initial_int: int = 1
var initial_hp_bonus: int = 0
var initial_can_swim: bool = false

# Debug/Cheat modes
var god_mode: bool = false

func set_class_stats(class_id: int):
	player_class = class_id
	initial_can_swim = false
	match class_id:
		0: # Balanced
			initial_str = 2
			initial_dex = 2
			initial_int = 2
			initial_hp_bonus = 1
		1: # Warrior
			initial_str = 4
			initial_dex = 1
			initial_int = 1
			initial_hp_bonus = 5
		2: # Rogue
			initial_str = 1
			initial_dex = 4
			initial_int = 1
			initial_hp_bonus = 0
		3: # Mage
			initial_str = 1
			initial_dex = 1
			initial_int = 4
			initial_hp_bonus = -2
		4: # Swimmer
			initial_str = 2
			initial_dex = 3
			initial_int = 1
			initial_hp_bonus = 2
			initial_can_swim = true
			initial_hp_bonus = 2
			initial_can_swim = true
		99: # Debug
			initial_str = 99
			initial_dex = 99
			initial_int = 99
			initial_hp_bonus = 900
			initial_can_swim = true
			
	# Initial Skills setup
	match class_id:
		0: initial_skills = ["heal", "blank_shot", "freeze"]
		1: initial_skills = [] # Warrior
		2: initial_skills = ["teleport"] # Rogue
		3: initial_skills = ["fireball", "lightning"] # Mage
		4: initial_skills = [] # Swimmer
		99: # Debug
			initial_skills = []
			for s in SkillDatabase.get_all_skills():
				initial_skills.append(s["id"])
	
var initial_skills: Array[String] = []

func set_custom_character(name: String, str_value: int, dex_value: int, int_value: int, hp_bonus: int, can_swim: bool, starting_skill: String = "", growth_focus: String = "balanced"):
	player_name = name.strip_edges()
	if player_name == "":
		player_name = "Hero"
	player_class = -1
	initial_str = str_value
	initial_dex = dex_value
	initial_int = int_value
	initial_hp_bonus = hp_bonus
	initial_can_swim = can_swim
	initial_skills = []
	if starting_skill != "":
		initial_skills.append(starting_skill)
	custom_growth_rates = _build_custom_growth_rates(growth_focus)

func _build_custom_growth_rates(growth_focus: String) -> Dictionary:
	match growth_focus:
		"power":
			return {"str": 0.9, "dex": 0.3, "int": 0.2, "hp": 3.0}
		"agility":
			return {"str": 0.3, "dex": 0.9, "int": 0.3, "hp": 2.0}
		"magic":
			return {"str": 0.2, "dex": 0.3, "int": 0.9, "hp": 1.5}
		"survival":
			return {"str": 0.5, "dex": 0.5, "int": 0.2, "hp": 4.0}
	return {"str": 0.5, "dex": 0.5, "int": 0.5, "hp": 2.0}

var growth_rates = {
	"str": 0.2, # Gain per level
	"dex": 0.2,
	"int": 0.2,
	"hp": 2.0
}

func get_growth_rates(class_id: int) -> Dictionary:
	# Returns { "str": float, "dex": float, "int": float, "hp": float }
	# High growth: 1.0 (every level)
	# Med growth: 0.5 (every 2 levels)
	# Low growth: 0.2 (every 5 levels)
	
	match class_id:
		-1:
			return custom_growth_rates
		0: # Balanced
			return {"str": 0.5, "dex": 0.5, "int": 0.5, "hp": 2.0}
		1: # Warrior
			return {"str": 1.0, "dex": 0.3, "int": 0.1, "hp": 4.0}
		2: # Rogue
			return {"str": 0.4, "dex": 1.0, "int": 0.3, "hp": 2.5}
		3: # Mage
			return {"str": 0.1, "dex": 0.3, "int": 1.0, "hp": 1.5}
		4: # Swimmer
			return {"str": 0.6, "dex": 0.7, "int": 0.2, "hp": 3.0}
		99: # Debug
			return {"str": 10.0, "dex": 10.0, "int": 10.0, "hp": 100.0}
	return {"str": 0.2, "dex": 0.2, "int": 0.2, "hp": 2.0}
