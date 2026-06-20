extends Node
class_name UIAnimations

## Utility class for reusable UI animations

## Fade in a Control node
static func fade_in(control: Control, duration: float = 0.3) -> void:
	if not control:
		return
	
	control.modulate.a = 0.0
	control.show()
	
	var tween = control.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(control, "modulate:a", 1.0, duration)

## Fade out a Control node
static func fade_out(control: Control, duration: float = 0.3, hide_after: bool = true) -> void:
	if not control:
		return
	
	var tween = control.create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(control, "modulate:a", 0.0, duration)
	
	if hide_after:
		tween.tween_callback(control.hide)

## Slide in from bottom
static func slide_in_bottom(control: Control, duration: float = 0.4, distance: float = 50.0) -> void:
	if not control:
		return
	
	var original_pos = control.position
	control.position.y += distance
	control.modulate.a = 0.0
	control.show()
	
	var tween = control.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_parallel(true)
	tween.tween_property(control, "position:y", original_pos.y, duration)
	tween.tween_property(control, "modulate:a", 1.0, duration * 0.7)

## Slide out to bottom
static func slide_out_bottom(control: Control, duration: float = 0.3, distance: float = 50.0, hide_after: bool = true) -> void:
	if not control:
		return
	
	var tween = control.create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_parallel(true)
	tween.tween_property(control, "position:y", control.position.y + distance, duration)
	tween.tween_property(control, "modulate:a", 0.0, duration * 0.7)
	
	if hide_after:
		tween.tween_callback(control.hide)

## Scale pop-in effect
static func scale_pop_in(control: Control, duration: float = 0.3) -> void:
	if not control:
		return
	
	control.scale = Vector2(0.8, 0.8)
	control.modulate.a = 0.0
	control.show()
	
	var tween = control.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_parallel(true)
	tween.tween_property(control, "scale", Vector2.ONE, duration)
	tween.tween_property(control, "modulate:a", 1.0, duration * 0.6)

## Scale pop-out effect
static func scale_pop_out(control: Control, duration: float = 0.2, hide_after: bool = true) -> void:
	if not control:
		return
	
	var tween = control.create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_parallel(true)
	tween.tween_property(control, "scale", Vector2(0.8, 0.8), duration)
	tween.tween_property(control, "modulate:a", 0.0, duration * 0.8)
	
	if hide_after:
		tween.tween_callback(control.hide)
		tween.tween_callback(func(): control.scale = Vector2.ONE)

## Pulse effect (for attention)
static func pulse(control: Control, scale_amount: float = 1.1, duration: float = 0.5) -> void:
	if not control:
		return
	
	var tween = control.create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(control, "scale", Vector2.ONE * scale_amount, duration / 2.0)
	tween.tween_property(control, "scale", Vector2.ONE, duration / 2.0)

## Shake effect (for errors or damage)
static func shake(control: Control, intensity: float = 5.0, duration: float = 0.3) -> void:
	if not control:
		return
	
	var original_pos = control.position
	var tween = control.create_tween()
	
	var shake_count = 8
	var shake_duration = duration / shake_count
	
	# 規則的な左右の揺れ
	for i in range(shake_count):
		var offset_x = intensity if i % 2 == 0 else -intensity
		var offset = Vector2(offset_x, 0)
		tween.tween_property(control, "position", original_pos + offset, shake_duration)
	
	# 最後に元の位置に戻す
	tween.tween_property(control, "position", original_pos, shake_duration)

