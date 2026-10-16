extends SceneTree

var failures := 0

func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run_test")

func run_test():
	root.size = Vector2i(1152, 648)
	var panel := Panel.new()
	panel.position = Vector2(50, 50)
	panel.size = Vector2(200, 100)
	root.add_child(panel)
	var header := Label.new()
	header.text = "Drag"
	panel.add_child(header)
	var drag = preload("res://ui/panel_drag.gd").attach(panel, header)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = Vector2(60, 60)
	drag._on_handle_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(160, 100)
	drag._input(motion)
	check(panel.position == Vector2(150, 90), "Panel did not follow drag")
	check(drag.displacement == Vector2(100, 40), "Layout displacement lost")
	press.pressed = false
	drag._input(press)
	motion.position += Vector2(100, 100)
	drag._input(motion)
	check(panel.position == Vector2(150, 90), "Panel moved after release")
	panel.position = Vector2(-100, -100)
	drag._clamp_panel()
	check(panel.position == Vector2.ZERO, "Panel escaped viewport")
	var log_ui = root.get_node("LogUI")
	log_ui._panel_drag.displacement = Vector2(30, -20)
	log_ui._apply_display_mode()
	await process_frame
	var normal_position: Vector2 = log_ui.log_panel.position
	for i in range(3):
		log_ui.toggle_visibility()
		await process_frame
	check(log_ui.log_panel.position.is_equal_approx(normal_position), "Log mode cycle reset drag position")
	panel.queue_free()
	print("PANEL_DRAG_TEST failures=", failures)
	quit(failures)
