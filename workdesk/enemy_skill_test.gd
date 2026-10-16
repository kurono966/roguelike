extends Node

class TestTurnManager extends TurnManager:
	func start_player_turn():
		pass # Inspect each turn before paralysis automatically skips the next one.

var main
var failures = 0

func _ready():
	call_deferred("_run")

func _check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _run():
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	var turns = TestTurnManager.new()
	main.add_child(turns)
	turns.setup(main)
	for group in ["enemies", "npcs", "allies"]:
		for actor in get_tree().get_nodes_in_group(group):
			actor.queue_free()
	await get_tree().process_frame
	main.player.position = Vector2(25, 25) * 32
	main.player.max_hp = 10000
	main.player.hp = 10000
	main.player.equipment_component.equipment_data.items.clear()
	main._traps.clear()
	for x in range(20, 36):
		for y in range(20, 36):
			main._map_data[x][y] = main.CellType.FLOOR
	main._setup_pathfinding()
	var enemy = load("res://actors/enemy/enemy.tscn").instantiate()
	enemy.position = Vector2(28, 25) * 32
	enemy.skill_id = "web_shot"
	enemy.attack_range = 4
	enemy.max_skill_cooldown = 3
	enemy.skill_cooldown = 0
	enemy.hp = 500
	enemy.max_hp = 500
	enemy.add_to_group("enemies")
	enemy.add_to_group("entities")
	main.add_child(enemy)
	main._calculate_fov()
	# Actor perception must work even when the player cannot see the caster.
	main.visibility_manager.visible_tiles[28][25] = false
	await turns.process_enemy_turns()
	_check(enemy.skill_cooldown == 3, "Ranged skill did not activate outside player FOV")
	_check(main.player.has_status_effect("paralysis"), "Web did not paralyze player")
	main.player.status_effects.clear()
	main._map_data[25][25] = main.CellType.GRASS
	await turns.process_enemy_turns()
	_check(enemy.skill_cooldown == 2, "Cooldown did not advance while target was hidden")
	main._map_data[25][25] = main.CellType.FLOOR
	main.player.status_effects.clear()
	enemy.position = Vector2(28, 25) * 32
	enemy.skill_cooldown = 1
	await turns.process_enemy_turns()
	_check(enemy.skill_cooldown == 3, "Skill did not reactivate after recovery")
	main.player.status_effects.clear()
	enemy.position = Vector2(26, 26) * 32
	enemy.skill_id = "paralyze_touch"
	enemy.attack_range = 1
	enemy.skill_cooldown = 0
	await turns.process_enemy_turns()
	_check(enemy.skill_cooldown == 3, "Melee skill did not activate diagonally")
	_check(main.player.has_status_effect("paralysis"), "Diagonal touch did not paralyze player")
	main.player.status_effects.clear()
	var npc = load("res://actors/enemy/enemy.tscn").instantiate()
	npc.position = Vector2(27, 26) * 32
	npc.hp = 500
	npc.max_hp = 500
	npc.is_npc = true
	npc.add_to_group("npcs")
	npc.add_to_group("entities")
	main.add_child(npc)
	await main._execute_enemy_skill_v2(enemy, Vector2i(27, 26))
	_check(npc.is_paralyzed(), "Touch effect did not disable NPC")
	npc.status_effects.clear()
	enemy.skill_id = "web_shot"
	await main._execute_enemy_skill_v2(enemy, Vector2i(27, 26))
	_check(npc.is_paralyzed(), "Web effect did not disable NPC")
	print("ENEMY_SKILL_TEST failures=", failures)
	await get_tree().create_timer(2.1).timeout
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
