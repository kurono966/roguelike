extends Node2D

var _elapsed = 0.0
var _frame = 0

func _init():
	# Above elevation/vegetation (1), below dropped items (4) and actors (5).
	z_index = 2

func _process(delta: float):
	_elapsed += delta
	if _elapsed < 0.12: return
	_elapsed = 0.0
	_frame = (_frame + 1) % 4
	queue_redraw()

func _draw():
	var size = float(MapDefinitions.TILE_SIZE)
	draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * size), Color(1.0, 0.20, 0.01, 0.36 + _frame * 0.025))
	for base in [Vector2(9, 29), Vector2(23, 27)]:
		var sway = float(_frame % 3 - 1)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-5, 0), base + Vector2(-6, -5),
			base + Vector2(-2, -10), base + Vector2(sway, -18),
			base + Vector2(3, -10), base + Vector2(6, -5), base + Vector2(5, 0)
		]), Color(1.0, 0.40, 0.025, 0.95))
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-3, 0), base + Vector2(-2, -6),
			base + Vector2(sway, -11), base + Vector2(3, -4), base + Vector2(3, 0)
		]), Color(1.0, 0.91, 0.32, 0.95))
