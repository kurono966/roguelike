class_name CombatManager
extends Node

var main_node: Node2D # Reference to main.gd
var tile_map: TileMap
var map_data: Array

func setup(main: Node2D):
	main_node = main
	tile_map = main.tile_map
	# map_data is dynamic in main, so we should access main.map_data directly or update it
	# But for read-access `main._map_data` is OK if public. 
	# Since `_map_data` is private `_`, we might need a getter or just access it if we trust Godot's permissiveness (which usually allows access).
	# Better: main exposes `get_map_data()` or similar. 
	# For now, I'll assume main has `_map_data` and strict mode might complain. 
	# I'll try to use main.get("_map_data") or main.map_data if I rename it.

const CellType = MapDefinitions.CellType
const MAP_WIDTH = MapDefinitions.MAP_WIDTH
const MAP_HEIGHT = MapDefinitions.MAP_HEIGHT
const TILE_SIZE = MapDefinitions.TILE_SIZE

func handle_attack(attacker, defender):
	var attacker_name = attacker.name
	if "enemy_name" in attacker:
		attacker_name = attacker.enemy_name
	elif attacker == main_node.player:
		attacker_name = "Player"
		
	var defender_name = defender.name
	if "enemy_name" in defender:
		defender_name = defender.enemy_name
	elif defender == main_node.player:
		defender_name = "Player"

	# Base Damage calculation
	var damage = 1
	if is_instance_valid(attacker):
		if attacker.get("attack_power") != null:
			damage = attacker.attack_power
		elif attacker.has_method("get_attack_power"):
			damage = attacker.get_attack_power()
			
	# Every character uses the same base accuracy unless individually modified.
	if is_instance_valid(attacker):
		var hit_chance = attacker.hit_rate if "hit_rate" in attacker else 0.85
		hit_chance = clamp(hit_chance, 0.0, 1.0)
		if randf() > hit_chance:
			print("Attack Missed! (Hit Rate: ", hit_chance, ")")
			_log("%s の攻撃は外れた！" % attacker_name, Color(0.7, 0.7, 0.7))
			return

	# Critical Check (if attacker is player)
	var is_crit = false
	if attacker == main_node.player:
		var c_rate = attacker.crit_rate if "crit_rate" in attacker else 0.05
		if randf() < c_rate:
			is_crit = true
			damage *= 2
			print("Critical Hit! (Rate: ", c_rate, ")")
	
	# Attack Animation (Bump)
	var tween = main_node.create_tween()
	var sprite = attacker.get_node_or_null("Sprite2D")
	
	if sprite:
		var start_pos = sprite.position
		if "sprite_offset" in attacker:
			start_pos = attacker.sprite_offset
			sprite.position = start_pos
			
		var target_pos = defender.position
		var dir = (target_pos - attacker.position).normalized()
		var bump_pos = start_pos + dir * 16.0
		
		tween.tween_property(sprite, "position", bump_pos, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "position", start_pos, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		tween.tween_interval(0.1)
		
	await tween.finished
	
	# Defense Calculation
	var def = 0
	if is_instance_valid(defender):
		if "defense_power" in defender:
			def = defender.defense_power
		elif "defense" in defender:
			def = defender.defense
			
	var pen = 0.0
	if is_instance_valid(attacker) and "penetration_rate" in attacker:
		pen = attacker.penetration_rate
		
	var effective_def = int(float(def) * (1.0 - pen))
	# Ensure defensive reduction isn't too punishing for player early on
	var final_damage = max(1, damage - effective_def)
	
	if is_instance_valid(defender):
		if defender.has_method("take_damage"):
			defender.take_damage(final_damage, attacker, ["normal"], is_crit)
	
	# 3. Apply Effect (Player -> Enemy)
	if attacker == main_node.player and is_instance_valid(defender) and attacker.has_method("get_on_hit_effects") and defender.has_method("apply_effect"):
		var effects_list = attacker.get_on_hit_effects()
		for effects in effects_list:
			if effects.has("burn"):
				var burn_data = effects["burn"]
				var chance = burn_data.get("chance", 0.0)
				if randf() < chance:
					var min_d = burn_data.get("min_duration", 3)
					var max_d = burn_data.get("max_duration", 10)
					var duration = randi_range(min_d, max_d)
					var burn_damage = burn_data.get("damage", 1)
					defender.apply_effect("burn", {"duration": duration, "damage": burn_damage})
		
		# Check Spark Core effect (Water conduction)
		if attacker.has_method("_check_equipment_effect") and attacker._check_equipment_effect("spark_core_effect"):
			var p_grid = tile_map.local_to_map(attacker.position)
			if main_node._map_data[p_grid.x][p_grid.y] == CellType.WATER:
				var chain_dmg = 4
				if "intelligence" in attacker:
					chain_dmg += attacker.intelligence
				main_node._apply_chain_lightning(attacker, defender, chain_dmg, 3, [])
	
	# 4. Apply Effect (Enemy -> Player)
	elif is_instance_valid(attacker) and "on_hit_effects" in attacker and not attacker.on_hit_effects.is_empty() and defender == main_node.player:
		# Check for Paralyze
		if attacker.on_hit_effects.has("paralyze"):
			var data = attacker.on_hit_effects["paralyze"]
			var chance = data.get("chance", 0.0)
			var roll = randf()
			print("Paralyze check: Risk %.2f vs Roll %.2f" % [chance, roll])
			
			if roll < chance:
				var dur = data.get("duration", 3)
				if main_node.player.has_method("apply_status_effect"):
					main_node.player.apply_status_effect("paralysis", dur)
					print("Applied paralysis to player")
				else:
					print("ERROR: Player is missing 'apply_status_effect' method!")
					_log("エラー: プレイヤーに効果適用メソッドがありません", Color.RED)

	# Knockback Logic (Enemy -> Player)
	if is_instance_valid(attacker) and "has_knockback" in attacker and attacker.has_knockback:
		var att_grid = tile_map.local_to_map(attacker.position)
		var def_grid = tile_map.local_to_map(defender.position)
		var knock_dir = def_grid - att_grid
		
		# Ensure valid direction (clamp to -1, 0, 1)
		knock_dir = Vector2i(sign(knock_dir.x), sign(knock_dir.y))
		
		print("Knockback Debug: Attacker ", att_grid, " Defender ", def_grid, " Dir ", knock_dir)
		
		if knock_dir != Vector2i.ZERO:
			var current_check = def_grid
			var land_pos = current_check
			
			# Check up to 10 tiles (or until map bounds)
			for i in range(1, 10):
				var next = current_check + knock_dir * i
				if next.x < 0 or next.x >= MAP_WIDTH or next.y < 0 or next.y >= MAP_HEIGHT:
					break
				
				# Use dynamic access to main._map_data
				var cell = main_node._map_data[next.x][next.y]
				# Stop at Walls, closed doors, or locked doors
				if cell == CellType.WALL or cell == CellType.DOOR_CLOSED or cell == CellType.DOOR_LOCKED:
					print("Knockback hit wall/door at ", next)
					break
				
				land_pos = next
			
			if land_pos != Vector2i(defender.position / TILE_SIZE):
				var target_pixel_pos = Vector2(land_pos) * TILE_SIZE
				
				# Animate Knockback
				var kb_tween = main_node.create_tween()
				kb_tween.set_parallel(true)
				kb_tween.tween_property(defender, "position", target_pixel_pos, 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
				
				print("Knockback! Pushed to ", land_pos)
				_log("%s は吹き飛ばされた！" % defender_name, Color(1.0, 0.5, 0.0))
				
				if defender == main_node.player:
					await kb_tween.finished
					if main_node.has_method("_calculate_fov"):
						main_node._calculate_fov()
					if main_node.has_method("_draw_map"):
						main_node._draw_map()

	print(attacker_name, " attacks ", defender_name, " for ", final_damage, " damage!")
	var crit_text = " (会心!)" if is_crit else ""
	var message = "%sの攻撃！ %sに%dのダメージを与えた。%s" % [attacker_name, defender_name, final_damage, crit_text]
	var is_player_atk = (attacker == main_node.player) if is_instance_valid(attacker) else false
	var color = Color(1.0, 0.5, 0.5) if is_crit else (Color.WHITE if is_player_atk else Color.PALE_VIOLET_RED)
	_log(message, color)

func _log(msg: String, color: Color = Color.WHITE):
	if main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log(msg, color)
