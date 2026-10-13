extends Node
# クリック移動(経路追従)の手動検証用ハーネス。
# 実行: godot --headless --path <project> res://workdesk/click_move_test/click_move_test.tscn

var main: Node2D = null
var start_time_ms: int = 0
var start_grid: Vector2i = Vector2i.ZERO
var first_target: Vector2i = Vector2i.ZERO
var second_target: Vector2i = Vector2i.ZERO
var first_requested: bool = false
var second_requested: bool = false

func _ready() -> void:
	main = load("res://world/main.tscn").instantiate()
	add_child(main)
	start_time_ms = Time.get_ticks_msec()
	print("TEST: main loaded. PlayerUi=", has_node("/root/PlayerUi"), " LogUI=", has_node("/root/LogUI"))

func _elapsed() -> int:
	return Time.get_ticks_msec() - start_time_ms

func _grid() -> Vector2i:
	return main.tile_map.local_to_map(main.player.position)

func _find_walkable(from: Vector2i, min_dist: int, max_dist: int) -> Vector2i:
	for dist in range(min_dist, max_dist + 1):
		for dx in range(-dist, dist + 1):
			for dy in range(-dist, dist + 1):
				if abs(dx) != dist and abs(dy) != dist:
					continue
				var g: Vector2i = from + Vector2i(dx, dy)
				if g.x < 1 or g.y < 1 or g.x >= main.MAP_WIDTH - 1 or g.y >= main.MAP_HEIGHT - 1:
					continue
				if main._is_walkable(g, main.player.can_swim):
					return g
	return Vector2i.ZERO

func _process(_delta: float) -> void:
	if main == null or not is_instance_valid(main.player):
		return

	if not first_requested and _elapsed() > 1500:
		first_requested = true
		start_grid = _grid()
		first_target = _find_walkable(start_grid, 4, 9)
		# 移動できない指定が正しく拒否されるか
		var denied: bool = not main._start_path_to(Vector2i(-5, -5))
		print("TEST: out_of_bounds_denied=", denied)
		main.request_move_to_tile(first_target)
		print("TEST: start=%s first_target=%s pending=%s" % [start_grid, first_target, main._has_pending_path_target])

	elif first_requested and not second_requested and (_grid() != start_grid or _elapsed() > 12000):
		second_requested = true
		second_target = _find_walkable(_grid(), 4, 9)
		main.request_move_to_tile(second_target)
		print("TEST: retarget at grid=%s -> %s (gen=%d, elapsed=%dms)" % [_grid(), second_target, main._path_generation, _elapsed()])

	elif second_requested:
		var g2: Vector2i = _grid()
		var arrived: bool = g2 == second_target and not main._is_path_following and not main._has_pending_path_target
		if arrived or _elapsed() > 30000:
			_finish()

var finished: bool = false

func _finish() -> void:
	if finished:
		return
	finished = true
	var g: Vector2i = _grid()
	var moved: bool = g != start_grid
	var reached: bool = g == second_target
	var healthy: bool = not main._is_processing_action and not main._has_pending_path_target
	print("TEST@FINAL: grid=%s start=%s moved=%s reached_second=%s" % [g, start_grid, moved, reached])
	print("TEST@FINAL: following=%s pending=%s lock=%s gen=%d" % [main._is_path_following, main._has_pending_path_target, main._is_processing_action, main._path_generation])
	print("TEST RESULT: ", "PASS" if (moved and healthy) else "FAIL")
	get_tree().quit(0 if (moved and healthy) else 1)
