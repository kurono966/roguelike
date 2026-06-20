class_name CrtEffectController
extends Node

var main_scene: Node2D

func setup(p_main_scene: Node2D):
	main_scene = p_main_scene
	_setup_crt_effect()

func _setup_crt_effect():
	# Disable CRT effect on Web to prevent shader/viewport scaling issues
	if OS.get_name() == "Web":
		return

	# Create CanvasLayer to hold the effect (ensure it renders on top)
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100 # Top layer
	main_scene.add_child(canvas_layer)
	
	# Create ColorRect for full screen shader
	var rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # Don't block mouse
	
	var shader = load("res://assets/shaders/crt_effect.gdshader")
	if not shader:
		print("Failed to load CRT shader")
		return
		
	var material = ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	
	# Add BackBufferCopy to capture screen
	var back_buffer = BackBufferCopy.new()
	back_buffer.copy_mode = BackBufferCopy.COPY_MODE_RECT
	back_buffer.rect = Rect2(0, 0, 1920, 1080) # Large enough area
	canvas_layer.add_child(back_buffer)
	
	canvas_layer.add_child(rect)
	print("CRT effect initiated.")
