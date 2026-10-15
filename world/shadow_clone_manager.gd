class_name ShadowCloneManager
extends Node2D

# 影の分身（ShadowClone）の生成・記録・再生を管理する。
# - 生成: 二重の薬（飲む/投げる）で spawn_clone() を呼ぶ。
# - 記録: プレイヤー/敵が行動した時 record() でそのターンの行動を影に残す。
# - 再生: ターン終了時に replay_pending() が「1ターン前に記録された行動」を影に実行させる。
# 影そのものが行動しても record はされない（is_replaying / actor is ShadowClone でガード）。

const TILE_SIZE = MapDefinitions.TILE_SIZE
const CLONE_SCENE = preload("res://world/shadow_clone.tscn")

var main_node: Node2D
var player
var clones: Array = []
var current_turn: int = 0
var is_replaying: bool = false


func setup(main: Node2D):
	main_node = main
	player = main.player


func clear_all() -> void:
	for c in clones.duplicate():
		if is_instance_valid(c):
			c.queue_free()
	clones.clear()


func clone_count() -> int:
	var n = 0
	for c in clones:
		if is_instance_valid(c) and c.turns_remaining > 0:
			n += 1
	return n


func get_clones_for(actor) -> Array:
	var out = []
	for c in clones:
		if is_instance_valid(c) and c.source == actor:
			out.append(c)
	return out


func _log(msg: String, color: Color) -> void:
	if main_node and main_node.has_node("/root/LogUI"):
		main_node.get_node("/root/LogUI").add_log(msg, color)


func _name_of(node) -> String:
	if not is_instance_valid(node):
		return "?"
	if "enemy_name" in node:
		return node.enemy_name
	if node == player:
		return "あなた"
	return str(node.name)


func _world_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / TILE_SIZE), int(pos.y / TILE_SIZE))


func _is_walkable(grid: Vector2i) -> bool:
	var mc = main_node.map_controller if main_node else null
	if mc and mc.has_method("is_walkable"):
		return mc.is_walkable(grid)
	return false


# 実体（entities グループ）がそのタイルに居るか。アイテムは除く。
func _occupied_by_real_actor(grid: Vector2i) -> bool:
	if not get_tree():
		return false
	for e in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if not (e is Node2D):
			continue
		if e.is_in_group("items"):
			continue
		var g = _world_to_grid(e.position)
		if g == grid:
			return true
	return false


func _enemy_at_grid(grid: Vector2i):
	if not get_tree():
		return null
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if _world_to_grid(e.position) == grid and ("hp" not in e or e.hp > 0):
			return e
	return null


# source の隣の歩行可能タイルを探す（無ければ source の位置）。影は実体ではないので重なってもよい。
func _find_adjacent_walkable(src_grid: Vector2i) -> Vector2i:
	var dirs = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1),
	]
	for d in dirs:
		var g = src_grid + d
		# 影は実体ではないので、エンティティと重なってもよい
		if _is_walkable(g):
			return g
	return src_grid


func spawn_clone(source, duration: int = 20) -> ShadowClone:
	if not is_instance_valid(source) or not (source is Node):
		return null
	var src_grid = _world_to_grid(source.position)
	# 影は実体ではないので、飲んだエンティティと同じ座標に生成する
	var clone: ShadowClone = CLONE_SCENE.instantiate()
	clone.position = source.position
	main_node.add_child(clone)
	clone.setup(source, main_node, duration, current_turn)
	clones.append(clone)
	_log("%s の影が動き出した！(%dターンの間、直近の行動を1ターン遅れで繰り返す)" % [_name_of(source), duration], Color(0.6, 0.6, 1.0))
	return clone


# actor のこのターンの行動を、actor を源に持つ各影へ記録する。
func record(actor, action: Dictionary) -> void:
	if is_replaying:
		return # 再生中の行動は記録しない（連鎖防止）
	if clones.is_empty():
		return
	if not is_instance_valid(actor):
		return
	if actor is ShadowClone:
		return # 影自身の行動は記録しない
	for c in clones:
		if is_instance_valid(c) and is_instance_valid(c.source) and c.source == actor:
			c.record_action(action, current_turn)


# 1ターン前に記録された行動を、各影に実行させる。turn_manager.end_player_turn() から呼ばれる。
func replay_pending() -> void:
	if clones.is_empty():
		return
	var target = current_turn - 1
	is_replaying = true
	for c in clones.duplicate():
		if not _prune(c):
			continue
		if target < 0:
			continue
		var action = c.get_action_for_turn(target)
		if action.is_empty():
			continue
		await _replay_action(c, action)
	is_replaying = false


# 存続時間の経過と無効な影の除去。現在ターンを進める。process_enemy_turns() の後に呼ばれる。
func tick() -> void:
	for c in clones.duplicate():
		if not _prune(c):
			continue
		c.turns_remaining -= 1
		if c.turns_remaining <= 0:
			_despawn(c, "影は薄れ消えた...")
	current_turn += 1


func _despawn(c, msg: String = "") -> void:
	if msg != "":
		_log(msg, Color(0.5, 0.5, 0.8))
	if is_instance_valid(c):
		c.queue_free()
	clones.erase(c)


# 除去すべき影なら除去して false、生きていれば true を返す。
func _prune(c) -> bool:
	if not is_instance_valid(c):
		clones.erase(c)
		return false
	if not is_instance_valid(c.source):
		_despawn(c, "影の源が失われた...")
		return false
	if "hp" in c.source and c.source.hp <= 0:
		_despawn(c, "影の源が倒れた...")
		return false
	if c.turns_remaining <= 0:
		_despawn(c, "影は薄れ消えた...")
		return false
	return true


func _replay_action(clone: ShadowClone, action: Dictionary) -> void:
	if not is_instance_valid(clone):
		return
	# 再生のたびに本体の最新ステータスを反映する
	clone._copy_combat_stats()
	match action.get("type", ""):
		"move":
			await _replay_move(clone, action)
		"attack":
			await _replay_attack(clone, action)
		"ranged":
			await _replay_ranged(clone, action)
		"skill":
			await _replay_skill(clone, action)
		"heal":
			clone.heal(int(action.get("amount", 0)))
		_:
			pass


func _replay_move(clone: ShadowClone, action: Dictionary) -> void:
	var dir: Vector2i = action.get("dir", Vector2i.ZERO)
	if dir == Vector2i.ZERO:
		return
	var from_grid = clone.get_grid()
	var to_grid = from_grid + dir
	# 影は壁もすり抜けられる
	var target = Vector2(to_grid) * TILE_SIZE
	var tw = main_node.create_tween()
	tw.tween_property(clone, "position", target, 0.08)
	await tw.finished


func _alive_target(node) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	if "hp" in node and node.hp <= 0:
		return false
	return true


# 攻撃対象の解決: 記録された対象が生きていればそれ、無ければ隣接する別ターゲット。
func _resolve_attack_target(clone: ShadowClone, action: Dictionary):
	var tref = action.get("target_ref")
	if is_instance_valid(tref) and tref != clone and tref != clone.source and _alive_target(tref):
		return tref
	# フォールバック: 隣接タイルの生きている敵 or プレイヤー（源自身は除く）
	var g = clone.get_grid()
	if get_tree():
		var candidates = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("player")
		for e in candidates:
			if not is_instance_valid(e) or e.is_queued_for_deletion():
				continue
			if e == clone or e == clone.source:
				continue
			if not _alive_target(e):
				continue
			var eg = _world_to_grid(e.position)
			if absi(eg.x - g.x) <= 1 and absi(eg.y - g.y) <= 1:
				return e
	return null


func _replay_attack(clone: ShadowClone, action: Dictionary) -> void:
	var foe = _resolve_attack_target(clone, action)
	if foe == null:
		return
	if main_node.has_method("_handle_attack"):
		await main_node._handle_attack(clone, foe)


func _replay_ranged(clone: ShadowClone, action: Dictionary) -> void:
	if not main_node.has_method("_handle_ranged_attack"):
		return
	var grid: Vector2i = action.get("target_grid", clone.get_grid())
	await main_node._handle_ranged_attack(clone, grid, int(action.get("damage", 1)), action.get("ptype", "arrow"))


func _replay_skill(clone: ShadowClone, action: Dictionary) -> void:
	var kind = action.get("kind", "")
	match kind:
		"heal":
			clone.heal(int(action.get("amount", 0)))
		"charge":
			var target_grid: Vector2i = action.get("target_grid", clone.get_grid())
			# 影は壁をすり抜けて移動
			var target = Vector2(target_grid) * TILE_SIZE
			var tw = main_node.create_tween()
			tw.tween_property(clone, "position", target, 0.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			await tw.finished
			if main_node.has_method("_spawn_skill_particles"):
				main_node._spawn_skill_particles(clone.position, "web", 0.3)
		"shot":
			var grid: Vector2i = action.get("target_grid", clone.get_grid())
			var dmg = int(action.get("damage", 0))
			var foe = _enemy_at_grid(grid)
			if foe == null:
				foe = _resolve_attack_target(clone, {"target_ref": null, "target_grid": grid})
			if foe != null and dmg > 0 and is_instance_valid(foe) and foe.has_method("take_damage"):
				var elems = action.get("elements", ["normal"])
				foe.take_damage(dmg, clone, elems)
				var world_pos = Vector2(grid) * TILE_SIZE + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
				if main_node.has_method("_spawn_skill_particles"):
					main_node._spawn_skill_particles(world_pos, action.get("particle", "fire"), 0.4)
		"burst":
			var bgrid: Vector2i = action.get("target_grid", clone.get_grid())
			var bdmg = int(action.get("damage", 0))
			var bradius = int(action.get("radius", 1))
			var belems = action.get("elements", ["normal"])
			if get_tree() and bdmg > 0:
				var bworld = Vector2(bgrid) * TILE_SIZE + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
				if main_node.has_method("_spawn_skill_particles"):
					main_node._spawn_skill_particles(bworld, action.get("particle", "fire"), 0.5)
				for e in get_tree().get_nodes_in_group("enemies"):
					if not is_instance_valid(e) or e.is_queued_for_deletion():
						continue
					if not _alive_target(e):
						continue
					var eg = _world_to_grid(e.position)
					if absi(eg.x - bgrid.x) <= bradius and absi(eg.y - bgrid.y) <= bradius and e.has_method("take_damage"):
						e.take_damage(bdmg, clone, belems)
		"self":
			var world_pos = clone.position + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
			if main_node.has_method("_spawn_skill_particles"):
				main_node._spawn_skill_particles(world_pos, action.get("particle", "buff"), 0.5)
		_:
			pass

