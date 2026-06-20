extends CanvasLayer

const UnifiedInventoryUIScene = preload("res://ui/unified_inventory_ui.tscn")
const SkillMenuScene = preload("res://ui/skill_menu.tscn")
const TradeUIScene = preload("res://ui/trade_ui.tscn")
const DialogMenuScene = preload("res://ui/dialog_menu.tscn")

var unified_ui
var skill_menu_ui
var trade_ui
var dialog_menu
var help_ui
var status_ui
var is_visible = false # Inventory visibility
var is_skill_visible = false
var is_trade_visible = false
var is_status_visible = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	unified_ui = UnifiedInventoryUIScene.instantiate()
	add_child(unified_ui)
	unified_ui.visible = false
	unified_ui.visibility_changed.connect(_on_inventory_visibility_changed)
	
	skill_menu_ui = SkillMenuScene.instantiate()
	add_child(skill_menu_ui)
	skill_menu_ui.visible = false
	skill_menu_ui.visibility_changed.connect(_on_skill_menu_visibility_changed)
	
	trade_ui = TradeUIScene.instantiate()
	add_child(trade_ui)
	trade_ui.visible = false
	trade_ui.visibility_changed.connect(_on_trade_visibility_changed)
	
	dialog_menu = DialogMenuScene.instantiate()
	add_child(dialog_menu)
	dialog_menu.visible = false
	dialog_menu.option_selected.connect(_on_dialog_option_selected)
	
	help_ui = preload("res://ui/help_ui.gd").new()
	add_child(help_ui)
	
	status_ui = preload("res://ui/status_ui.gd").new()
	add_child(status_ui)
	status_ui.visibility_changed.connect(_on_status_visibility_changed)
	
	print("GameUI loaded successfully")
	
	_setup_tooltip()

var tooltip_panel: PanelContainer
var tooltip_label: Label # Compatibility
var tooltip_title_label: Label
var tooltip_body_label: Label
var tooltip_override_position = null

func _setup_tooltip():
	tooltip_panel = PanelContainer.new()
	tooltip_panel.visible = false
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.modulate.a = 0.95
	add_child(tooltip_panel)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.85) # Very dark gray-blue, translucent
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.25, 0.28, 1.0) # Muted metallic
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	tooltip_panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	tooltip_panel.add_child(vbox)
	
	tooltip_title_label = Label.new()
	tooltip_title_label.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25)) # Dull Gold
	tooltip_title_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(tooltip_title_label)
	
	tooltip_body_label = Label.new()
	tooltip_body_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85)) # Warm off-white
	tooltip_body_label.add_theme_font_size_override("font_size", 11)
	tooltip_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_body_label.custom_minimum_size = Vector2(220, 0)
	vbox.add_child(tooltip_body_label)
	
	# Fallback/compatibility
	tooltip_label = tooltip_body_label

func _process(delta):
	if tooltip_panel.visible:
		var base_pos = get_viewport().get_mouse_position()
		if tooltip_override_position != null:
			base_pos = tooltip_override_position
		
		# Offset slightly to not cover cursor
		tooltip_panel.position = base_pos + Vector2(16, 16)
		
		# Keep within screen bounds (basic check)
		var vp_size = get_viewport().get_visible_rect().size
		if tooltip_panel.position.x + tooltip_panel.size.x > vp_size.x:
			tooltip_panel.position.x = base_pos.x - tooltip_panel.size.x - 4
		if tooltip_panel.position.y + tooltip_panel.size.y > vp_size.y:
			tooltip_panel.position.y = base_pos.y - tooltip_panel.size.y - 4

func show_tooltip(text: String):
	if text == "":
		hide_tooltip()
		return
	
	var lines = text.split("\n", true, 1)
	var title = ""
	var body = ""
	
	if lines.size() > 0:
		title = lines[0].strip_edges()
	if lines.size() > 1:
		body = lines[1].strip_edges()
		
	if title != "":
		tooltip_title_label.text = "✦ " + title
		tooltip_title_label.visible = true
	else:
		tooltip_title_label.visible = false
		
	if body != "":
		tooltip_body_label.text = body
		tooltip_body_label.visible = true
	else:
		tooltip_body_label.visible = false
		
	tooltip_panel.visible = true
	tooltip_panel.size = Vector2.ZERO # Reset size to auto-fit

func hide_tooltip():
	if tooltip_panel:
		tooltip_panel.visible = false

func _on_inventory_visibility_changed():
	is_visible = unified_ui.visible

func _on_skill_menu_visibility_changed():
	is_skill_visible = skill_menu_ui.visible

func _on_trade_visibility_changed():
	is_trade_visible = trade_ui.visible

func _on_status_visibility_changed():
	is_status_visible = status_ui.visible

func toggle_ui():
	# Close status if open
	if is_status_visible:
		status_ui.close()
		return

	# Close skill menu if open
	if is_skill_visible:
		skill_menu_ui.visible = false # Direct set to trigger signal/logic
		return

	if is_visible:
		unified_ui.visible = false
		unified_ui.set_throw_mode(false) # Ensure mode is reset on close
	else:
		unified_ui.visible = true
		unified_ui.set_throw_mode(false) # Ensure normal mode
		var player = get_tree().get_first_node_in_group("player")
		if player:
			unified_ui.initialize(player)

func open_throw_selection():
	if is_skill_visible:
		skill_menu_ui.visible = false
		
	# Force open if closed, or just switch mode if open
	unified_ui.visible = true
	unified_ui.set_throw_mode(true)
	var player = get_tree().get_first_node_in_group("player")

func open_trade_menu(npc):
	# Close other UIs
	if is_visible:
		unified_ui.visible = false
	if is_skill_visible:
		skill_menu_ui.visible = false
	if is_status_visible:
		status_ui.close()
	
	# Open trade UI
	var player = get_tree().get_first_node_in_group("player")
	if player:
		trade_ui.initialize(player, npc)
	trade_ui.visible = true

func toggle_skills():
	# Close status if open
	if is_status_visible:
		status_ui.close()
		return
		
	# Close inventory if open
	if is_visible:
		unified_ui.visible = false
		return
		
	if is_skill_visible:
		skill_menu_ui.visible = false
	else:
		skill_menu_ui.visible = true
		var player = get_tree().get_first_node_in_group("player")
		if player:
			skill_menu_ui.initialize(player)

func toggle_help():
	if is_visible:
		unified_ui.visible = false
	if is_skill_visible:
		skill_menu_ui.visible = false
	if is_status_visible:
		status_ui.close()
		
	if help_ui.visible:
		help_ui.close()
	else:
		help_ui.open()

func toggle_status():
	if is_visible:
		unified_ui.visible = false
	if is_skill_visible:
		skill_menu_ui.visible = false
	if help_ui.visible:
		help_ui.close()
		
	if is_status_visible:
		status_ui.close()
	else:
		status_ui.open()

func show_dialog_menu(title: String, options: Array):
	dialog_menu.show_dialog(title, options)

func _on_dialog_option_selected(option: String):
	# This will be handled by the main game logic
	# We'll emit a signal or call a callback
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and main_node.has_method("_handle_dialog_choice"):
		main_node._handle_dialog_choice(option)
	else:
		# Close others
		if is_visible: toggle_ui()
		if is_skill_visible: toggle_skills()
		help_ui.open()

func add_log(message: String, color: Color = Color.WHITE) -> void:
	var log_ui_node = get_tree().root.get_node_or_null("LogUI")
	if log_ui_node and log_ui_node.has_method("add_log"):
		log_ui_node.add_log(message, color)
