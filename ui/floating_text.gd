extends Node2D

const CUSTOM_FONT = preload("res://assets/fonts/NotoSansJP-ExtraBold.ttf")

var velocity: Vector2 = Vector2.ZERO
var gravity: float = 220.0  # Gravitational pull in pixels/sec^2
var elapsed: float = 0.0
var duration: float = 0.8
var is_critical: bool = false
var original_scale: Vector2 = Vector2.ONE

func set_text(text: String, color: Color = Color.WHITE, is_crit: bool = false):
	$Label.text = text
	$Label.modulate = color
	is_critical = is_crit
	
	# Apply bold premium font
	$Label.add_theme_font_override("font", CUSTOM_FONT)
	$Label.add_theme_font_size_override("font_size", 18 if is_critical else 14)
	
	if is_critical:
		# Juicy golden outline for critical hits
		$Label.add_theme_color_override("font_outline_color", Color(1.0, 0.75, 0.0))
		$Label.add_theme_constant_override("outline_size", 6)
		original_scale = Vector2(1.5, 1.5)
	else:
		# Clean thick black outline for normal hits/healing
		$Label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		$Label.add_theme_constant_override("outline_size", 4)
		original_scale = Vector2(1.0, 1.0)

func _ready():
	# Launch in a compact upward arc (closer to the character's head)
	var angle = randf_range(-1.2, -0.6) # Up-right
	if randf() < 0.5:
		angle = randf_range(-2.5, -1.9) # Up-left
		
	var speed = randf_range(65.0, 85.0)
	if is_critical:
		speed = randf_range(90.0, 115.0) # Jump slightly higher for crits
		
	velocity = Vector2(cos(angle), sin(angle)) * speed
	
	# Elastic scale pop-in
	scale = Vector2.ZERO
	var pop_tween = create_tween()
	pop_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop_tween.tween_property(self, "scale", original_scale, 0.18)
	
	# Smooth fade out at the end
	var fade_tween = create_tween()
	fade_tween.tween_interval(duration * 0.55)
	fade_tween.tween_property(self, "modulate:a", 0.0, duration * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade_tween.tween_callback(queue_free)

func _process(delta: float):
	elapsed += delta
	# Apply gravity and velocity
	velocity.y += gravity * delta
	position += velocity * delta
	
	# Wiggle critical text slightly
	if is_critical and elapsed < duration:
		$Label.position = Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))

