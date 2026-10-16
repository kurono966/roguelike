extends Node

# 見出しだけで移動を開始し、内容のクリックやスクロールを保つ。
var panel: Control
var handle: Control
var displacement := Vector2.ZERO
var _dragging := false
var _last_mouse := Vector2.ZERO

static func attach(target: Control, grip: Control) -> Node:
	var drag = load("res://ui/panel_drag.gd").new()
	drag.panel = target
	drag.handle = grip
	target.add_child(drag)
	return drag

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.tooltip_text = "ドラッグで移動"
	handle.gui_input.connect(_on_handle_input)
	get_viewport().size_changed.connect(_clamp_deferred)

func _on_handle_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging = true
		_last_mouse = event.global_position
		handle.accept_event()

func _input(event: InputEvent):
	if not _dragging: return
	if not panel.is_visible_in_tree():
		_dragging = false
		return
	if event is InputEventMouseMotion:
		var mouse: Vector2 = event.position
		var before := panel.global_position
		panel.global_position += mouse - _last_mouse
		_clamp_panel()
		displacement += panel.global_position - before
		_last_mouse = mouse
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
		get_viewport().set_input_as_handled()

func _notification(what: int):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_dragging = false

func _clamp_deferred():
	call_deferred("_clamp_panel")

func _clamp_panel():
	var available := panel.get_viewport_rect().size
	panel.global_position = panel.global_position.clamp(Vector2.ZERO, (available - panel.size).max(Vector2.ZERO))
