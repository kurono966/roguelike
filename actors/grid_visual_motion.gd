extends RefCounted

# Actor roots hold tile positions. Only the sprite animates between tiles.
static func reset(actor: Node2D) -> void:
	if actor.get("_move_tween") != null:
		var movement: Tween = actor.get("_move_tween")
		if movement.is_valid():
			movement.kill()
	if actor.has_meta("position_feedback_tween"):
		var feedback: Tween = actor.get_meta("position_feedback_tween")
		if feedback and feedback.is_valid():
			feedback.kill()
		actor.remove_meta("position_feedback_tween")
	if actor.get("is_moving") != null:
		actor.set("is_moving", false)
	var sprite = actor.get_node_or_null("Sprite2D")
	if sprite:
		sprite.position = actor.get("sprite_offset") if actor.get("sprite_offset") != null else Vector2(16, 16)
	var light = actor.get_node_or_null("PointLight2D")
	if light:
		light.position = Vector2(16, 16)

static func bump(actor: Node2D, direction: Vector2, distance: float, outward_time: float, return_time: float) -> Tween:
	reset(actor)
	var tween = actor.create_tween()
	actor.set_meta("position_feedback_tween", tween)
	var sprite = actor.get_node_or_null("Sprite2D")
	if sprite:
		var origin: Vector2 = sprite.position
		tween.tween_property(sprite, "position", origin + direction * distance, outward_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "position", origin, return_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		tween.tween_interval(outward_time + return_time)
	return tween

static func slide(actor: Node2D, destination: Vector2, duration: float, via = null) -> Tween:
	reset(actor)
	var previous_position = actor.position
	actor.position = destination.snapped(Vector2(32, 32))
	var tween = actor.create_tween()
	actor.set("_move_tween", tween)
	if actor.get("is_moving") != null:
		actor.set("is_moving", true)
	var sprite = actor.get_node_or_null("Sprite2D")
	if sprite:
		var origin: Vector2 = sprite.position
		sprite.position += previous_position - actor.position
		if via != null:
			tween.tween_property(sprite, "position", Vector2(via) - actor.position + origin, duration / 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			duration *= 2.0 / 3.0
		tween.tween_property(sprite, "position", origin, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_interval(duration)
	if actor.get("is_moving") != null:
		tween.tween_callback(func(): actor.set("is_moving", false))
	return tween
