extends SceneTree

func _initialize():
	var player = load("res://actors/player.gd").new()
	player.base_known_skills.clear()
	player.strength = 0
	player.dexterity = 0
	player.intelligence = 4
	player.level = 1
	var near = player.get_nearby_skill_unlocks().filter(func(skill): return skill.id == "fireball")
	assert(near.size() == 1 and near[0].missing == 5, "Exactly five missing points must be included")
	assert(near[0].details.has("知力 +4") and near[0].details.has("紫 +1"), "Base and color deficits must both count")
	assert(not near[0].level_ready and near[0].required_level == 2, "Level must be displayed separately")
	player.intelligence = 3
	assert(not player.get_nearby_skill_unlocks().any(func(skill): return skill.id == "fireball"), "Six missing points must be excluded")
	player.intelligence = 99
	near = player.get_nearby_skill_unlocks().filter(func(skill): return skill.id == "fireball")
	assert(near.size() == 1 and near[0].missing == 1, "Excess intellect must not offset missing purple")
	player.connector_affinity.purple = 1
	near = player.get_nearby_skill_unlocks().filter(func(skill): return skill.id == "fireball")
	assert(near.size() == 1 and near[0].missing == 0, "Excess stats must not offset other deficits")
	player.base_known_skills.append("fireball")
	assert(not player.get_nearby_skill_unlocks().any(func(skill): return skill.id == "fireball"), "Learned skill must not appear")
	assert(player.get_nearby_skill_unlocks_text().contains("必要Lv."), "Required level missing from status text")
	var all_skills = player.get_nearby_skill_unlocks(-1, true)
	assert(all_skills.size() == player.SKILL_LEARNING_REQUIREMENTS.size(), "Full list omits natural skills")
	for index in range(1, all_skills.size()):
		assert(all_skills[index - 1].missing <= all_skills[index].missing, "Full list not sorted by shortfall")
	var full_text = player.get_all_natural_skill_requirements_text()
	assert(full_text.contains("習得済") and full_text.contains("必要：Lv.") and full_text.contains("紫 1"), "Full list missing learned state or complete requirements")
	player.free()
	print("NEARBY_SKILL_TEST passed")
	quit()
