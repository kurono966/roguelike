extends Control

signal ui_visibility_changed

var panel: PanelContainer
var is_visible: bool = false

var master_volume_slider: HSlider
var master_volume_label: Label
var sfx_volume_slider: HSlider
var sfx_volume_label: Label

var master_bus_index: int = -1
var sfx_bus_index: int = -1

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	
	# Get bus indices
	master_bus_index = AudioServer.get_bus_index("Master")
	sfx_bus_index = AudioServer.get_bus_index("SFX")
	
	# Create panel - use absolute positioning to ensure centering
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2.ZERO
	panel.custom_minimum_size = Vector2(84, 52)
	panel.add_theme_stylebox_override("panel", _get_panel_style())
	add_child(panel)
	
	# Center the panel after it's added to the scene
	call_deferred("_center_panel")
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	
	# Header
	var header = Label.new()
	header.text = "設定"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	vbox.add_child(header)
	
	# Master Volume
	var master_vbox = VBoxContainer.new()
	master_vbox.add_theme_constant_override("separation", 2)
	vbox.add_child(master_vbox)
	
	var master_label = Label.new()
	master_label.text = "マスター"
	master_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85))
	master_vbox.add_child(master_label)
	
	var master_hbox = HBoxContainer.new()
	master_hbox.add_theme_constant_override("separation", 6)
	master_vbox.add_child(master_hbox)
	
	master_volume_slider = HSlider.new()
	master_volume_slider.min_value = -80
	master_volume_slider.max_value = 0
	master_volume_slider.step = 1
	master_volume_slider.custom_minimum_size = Vector2(90, 0)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	master_hbox.add_child(master_volume_slider)
	
	master_volume_label = Label.new()
	master_volume_label.text = "0 dB"
	master_volume_label.custom_minimum_size = Vector2(35, 0)
	master_volume_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	master_hbox.add_child(master_volume_label)
	
	# SFX Volume
	var sfx_vbox = VBoxContainer.new()
	sfx_vbox.add_theme_constant_override("separation", 2)
	vbox.add_child(sfx_vbox)
	
	var sfx_label = Label.new()
	sfx_label.text = "効果音"
	sfx_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85))
	sfx_vbox.add_child(sfx_label)
	
	var sfx_hbox = HBoxContainer.new()
	sfx_hbox.add_theme_constant_override("separation", 6)
	sfx_vbox.add_child(sfx_hbox)
	
	sfx_volume_slider = HSlider.new()
	sfx_volume_slider.min_value = -80
	sfx_volume_slider.max_value = 0
	sfx_volume_slider.step = 1
	sfx_volume_slider.custom_minimum_size = Vector2(90, 0)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	sfx_hbox.add_child(sfx_volume_slider)
	
	sfx_volume_label = Label.new()
	sfx_volume_label.text = "0 dB"
	sfx_volume_label.custom_minimum_size = Vector2(35, 0)
	sfx_volume_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sfx_hbox.add_child(sfx_volume_label)
	
	# Initialize values
	_load_volume_settings()

func _get_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.85)
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.25, 0.28, 1.0)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style

func _center_panel():
	var viewport_size = get_viewport().get_visible_rect().size
	panel.position = (viewport_size - panel.size) / 2

func _load_volume_settings():
	if master_bus_index >= 0:
		var vol = AudioServer.get_bus_volume_db(master_bus_index)
		master_volume_slider.value = vol
		_update_master_label(vol)
	
	if sfx_bus_index >= 0:
		var vol = AudioServer.get_bus_volume_db(sfx_bus_index)
		sfx_volume_slider.value = vol
		_update_sfx_label(vol)

func _on_master_volume_changed(value: float):
	if master_bus_index >= 0:
		AudioServer.set_bus_volume_db(master_bus_index, value)
		_update_master_label(value)

func _on_sfx_volume_changed(value: float):
	if sfx_bus_index >= 0:
		AudioServer.set_bus_volume_db(sfx_bus_index, value)
		_update_sfx_label(value)

func _update_master_label(value: float):
	if value <= -80:
		master_volume_label.text = "ミュート"
	else:
		master_volume_label.text = str(int(value)) + " dB"

func _update_sfx_label(value: float):
	if value <= -80:
		sfx_volume_label.text = "ミュート"
	else:
		sfx_volume_label.text = str(int(value)) + " dB"

func open():
	visible = true
	is_visible = true
	_load_volume_settings()
	ui_visibility_changed.emit()

func close():
	visible = false
	is_visible = false
	ui_visibility_changed.emit()

func _input(event):
	if not visible:
		return
	
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
