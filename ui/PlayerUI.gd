extends CanvasLayer

const UIAnimations = preload("res://ui/ui_animations.gd")

# Status UI references
var status_panel: PanelContainer
var hp_bar: ProgressBar
var hp_label: Label
var mp_bar: ProgressBar
var mp_label: Label
var exp_bar: ProgressBar
var exp_label: Label

var level_val_label: Label
var gold_val_label: Label
var hunger_val_label: Label
var turn_val_label: Label

# Compatibility dummy references
var level_label: Label
var gold_label: Label
var hunger_label: Label
var turn_label: Label
var floor_label: Label
var hp_container: Control

# Tween & State
var current_tween: Tween = null
var _last_active_skill_id: String = ""

# Skill Bar
var shortcut_panel: PanelContainer
var skill_bar_container: HBoxContainer
const MAX_SKILL_SLOTS = 9

# --- Drag & Drop state ---
var _drag_source_slot: int = -1      # drag started from skill bar slot index (-1 = none)
var _drag_ghost: Control = null      # ghost icon following mouse
var _drag_skill_id: String = ""      # skill being dragged
var _drag_from_menu: bool = false    # true = drag originated from skill menu
var _drag_mouse_start: Vector2 = Vector2.ZERO  # position when mouse pressed on slot
var _pending_drag_slot: int = -1     # slot waiting to start drag (after threshold)
var _pending_drag_skill: String = "" # skill waiting to be dragged
const DRAG_THRESHOLD: float = 6.0   # pixels to move before drag starts

# Ammo & Weapon UI
var _info_container: VBoxContainer
var ammo_label: Label
var weapon_label: Label

func _ready():
	# 1. Clean slate: hide original .tscn nodes
	if has_node("HPContainer"):
		$HPContainer.visible = false
		$HPContainer.queue_free()
	if has_node("FloorContainer"):
		$FloorContainer.visible = false
		$FloorContainer.queue_free()
		
	# Populate dummy elements to prevent external script reference crashes
	level_label = Label.new()
	gold_label = Label.new()
	hunger_label = Label.new()
	turn_label = Label.new()
	floor_label = Label.new()
	hp_container = Control.new()
	
	# 2. Build consolidated Status Panel
	status_panel = PanelContainer.new()
	status_panel.name = "StatusPanel"
	status_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	status_panel.offset_left = 20
	status_panel.offset_top = 20
	status_panel.custom_minimum_size = Vector2(250, 260)
	status_panel.add_theme_stylebox_override("panel", get_panel_style())
	add_child(status_panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	status_panel.add_child(vbox)
	
	# Header
	var header = Label.new()
	header.text = "✦ STATUS ✦"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25)) # Dull Gold
	vbox.add_child(header)
	
	# Separator line
	var sep1 = ColorRect.new()
	sep1.color = Color(0.25, 0.25, 0.28, 0.4)
	sep1.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(sep1)
	
	# HP Bar Row
	var hp_hbox = HBoxContainer.new()
	hp_hbox.add_theme_constant_override("separation", 6)
	var hp_lbl = Label.new()
	hp_lbl.text = "HP"
	hp_lbl.custom_minimum_size = Vector2(30, 0)
	hp_lbl.add_theme_font_size_override("font_size", 12)
	hp_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	hp_hbox.add_child(hp_lbl)
	
	hp_bar = create_progress_bar(Color(0.48, 0.15, 0.15)) # Deep red-brown
	hp_hbox.add_child(hp_bar)
	
	hp_label = Label.new()
	hp_label.add_theme_font_size_override("font_size", 11)
	hp_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85)) # Warm off-white
	hp_hbox.add_child(hp_label)
	vbox.add_child(hp_hbox)
	
	# MP Bar Row
	var mp_hbox = HBoxContainer.new()
	mp_hbox.add_theme_constant_override("separation", 6)
	var mp_lbl = Label.new()
	mp_lbl.text = "MP"
	mp_lbl.custom_minimum_size = Vector2(30, 0)
	mp_lbl.add_theme_font_size_override("font_size", 12)
	mp_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	mp_hbox.add_child(mp_lbl)
	
	mp_bar = create_progress_bar(Color(0.18, 0.24, 0.45)) # Muted indigo
	mp_hbox.add_child(mp_bar)
	
	mp_label = Label.new()
	mp_label.add_theme_font_size_override("font_size", 11)
	mp_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85))
	mp_hbox.add_child(mp_label)
	vbox.add_child(mp_hbox)

	# EXP Bar Row
	var exp_hbox = HBoxContainer.new()
	exp_hbox.add_theme_constant_override("separation", 6)
	var exp_lbl = Label.new()
	exp_lbl.text = "EXP"
	exp_lbl.custom_minimum_size = Vector2(30, 0)
	exp_lbl.add_theme_font_size_override("font_size", 12)
	exp_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	exp_hbox.add_child(exp_lbl)
	
	exp_bar = create_progress_bar(Color(0.2, 0.4, 0.4)) # Muted slate teal
	exp_hbox.add_child(exp_bar)
	
	exp_label = Label.new()
	exp_label.add_theme_font_size_override("font_size", 11)
	exp_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85))
	exp_hbox.add_child(exp_label)
	vbox.add_child(exp_hbox)
	
	# Separator line 2
	var sep2 = ColorRect.new()
	sep2.color = Color(0.25, 0.25, 0.28, 0.4)
	sep2.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(sep2)
	
	# Grid Container for info labels
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)
	
	# Lv Label
	var lv_hbox = HBoxContainer.new()
	var lv_lbl = Label.new()
	lv_lbl.text = "Lv: "
	lv_lbl.add_theme_font_size_override("font_size", 12)
	lv_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	lv_hbox.add_child(lv_lbl)
	level_val_label = Label.new()
	level_val_label.text = "1"
	level_val_label.add_theme_font_size_override("font_size", 12)
	level_val_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85))
	lv_hbox.add_child(level_val_label)
	grid.add_child(lv_hbox)
	
	# Turn Label
	var turn_hbox = HBoxContainer.new()
	var turn_lbl = Label.new()
	turn_lbl.text = "Turn: "
	turn_lbl.add_theme_font_size_override("font_size", 12)
	turn_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	turn_hbox.add_child(turn_lbl)
	turn_val_label = Label.new()
	turn_val_label.text = "0"
	turn_val_label.add_theme_font_size_override("font_size", 12)
	turn_val_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85))
	turn_hbox.add_child(turn_val_label)
	grid.add_child(turn_hbox)
	
	# Gold Label
	var gold_hbox = HBoxContainer.new()
	var gold_lbl = Label.new()
	gold_lbl.text = "Gold: "
	gold_lbl.add_theme_font_size_override("font_size", 12)
	gold_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	gold_hbox.add_child(gold_lbl)
	gold_val_label = Label.new()
	gold_val_label.text = "0"
	gold_val_label.add_theme_font_size_override("font_size", 12)
	gold_val_label.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25)) # Dull Gold
	gold_hbox.add_child(gold_val_label)
	grid.add_child(gold_hbox)
	
	# Hunger Label
	var hunger_hbox = HBoxContainer.new()
	var hunger_lbl = Label.new()
	hunger_lbl.text = "Hunger: "
	hunger_lbl.add_theme_font_size_override("font_size", 12)
	hunger_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	hunger_hbox.add_child(hunger_lbl)
	hunger_val_label = Label.new()
	hunger_val_label.text = "100/100"
	hunger_val_label.add_theme_font_size_override("font_size", 12)
	hunger_val_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85))
	hunger_hbox.add_child(hunger_val_label)
	grid.add_child(hunger_hbox)

	# Pulse animation on ready
	UIAnimations.pulse(status_panel, 1.02, 0.6)

	# Initialize Skills shortcut bar
	call_deferred("_create_skill_bar_deferred")

func _process(_delta):
	# Update active skill highlight dynamically
	var main_node = get_tree().get_first_node_in_group("main")
	var active_skill_id = ""
	if main_node and main_node.get("target_manager") and main_node.target_manager.is_active():
		var skill_data = main_node.target_manager.targeting_skill
		if skill_data and skill_data.has("id"):
			active_skill_id = skill_data.id
			
	if active_skill_id != _last_active_skill_id:
		_last_active_skill_id = active_skill_id
		_refresh_slot_borders()

func _create_skill_bar_deferred():
	create_skill_bar()

# --- UI Styling Helpers ---

func get_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.85) # Very dark gray-blue, translucent
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.25, 0.28, 1.0) # Muted metallic
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	return style

func get_slot_style(is_filled: bool, is_selected: bool) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	if is_selected:
		style.bg_color = Color(0.12, 0.12, 0.15, 0.9)
		style.set_border_width_all(2)
		style.border_color = Color(0.85, 0.68, 0.25, 1.0) # Gold highlight
	elif is_filled:
		style.bg_color = Color(0.08, 0.08, 0.1, 0.85)
		style.set_border_width_all(1)
		style.border_color = Color(0.25, 0.25, 0.28, 1.0) # Muted border
	else:
		style.bg_color = Color(0.04, 0.04, 0.05, 0.3) # Dim background
		style.set_border_width_all(1)
		style.border_color = Color(0.12, 0.12, 0.15, 0.4) # Dim border
	style.set_corner_radius_all(3)
	return style

func create_progress_bar(fill_color: Color) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(140, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	# Background style
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.14, 1.0)
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	
	# Fill style
	var fg = StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fg)
	
	return bar

# --- Update Methods called from Game logic ---

func update_hp(current_hp: int, max_hp: int) -> void:
	if not hp_bar or not hp_label: return
	hp_bar.max_value = max_hp
	
	if current_tween:
		current_tween.kill()
		
	current_tween = create_tween()
	current_tween.set_ease(Tween.EASE_OUT)
	current_tween.set_trans(Tween.TRANS_CUBIC)
	current_tween.tween_property(hp_bar, "value", float(current_hp), 0.3)
	
	hp_label.text = "%d/%d" % [current_hp, max_hp]

func update_mp(current_mp: int, max_mp: int) -> void:
	if not mp_bar or not mp_label: return
	mp_bar.max_value = max_mp
	mp_bar.value = current_mp
	mp_label.text = "%d/%d" % [current_mp, max_mp]

func update_exp(current_exp: int, exp_needed: int) -> void:
	if not exp_bar or not exp_label: return
	exp_bar.max_value = exp_needed
	exp_bar.value = current_exp
	exp_label.text = "%d/%d" % [current_exp, exp_needed]

func update_level(new_level: int) -> void:
	if level_val_label:
		level_val_label.text = str(new_level)

func update_gold(new_gold: int) -> void:
	if gold_val_label:
		gold_val_label.text = str(new_gold)

func update_hunger(current_hunger: int, max_hunger: int) -> void:
	if hunger_val_label:
		var ratio = float(current_hunger) / max(1, max_hunger)
		hunger_val_label.text = "%d/%d" % [current_hunger, max_hunger]
		
		var color: Color
		if ratio <= 0.1:
			color = Color(0.75, 0.2, 0.2)
		elif ratio <= 0.3:
			color = Color(0.75, 0.45, 0.15)
		else:
			color = Color(0.9, 0.88, 0.85)
		hunger_val_label.add_theme_color_override("font_color", color)

func update_turns(turn_count: int) -> void:
	if turn_val_label:
		turn_val_label.text = str(turn_count)

func update_floor(floor_val: Variant):
	var floor_str = ""
	if floor_val is String:
		floor_str = floor_val
	elif floor_val == 0:
		floor_str = "地上"
	else:
		floor_str = "B%dF" % floor_val
		
	var main_node = get_tree().get_first_node_in_group("main")
	if main_node and main_node.get("minimap_controller"):
		main_node.minimap_controller.update_floor_label(floor_str)

# --- Ammo & Weapon Panel ---

func _ensure_info_container():
	if _info_container: return
	_info_container = VBoxContainer.new()
	_info_container.name = "BottomLeftInfo"
	_info_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info_container.offset_left = 20
	_info_container.offset_bottom = -160 # Aligned with the log panel
	_info_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info_container)

func create_ammo_label_if_needed():
	if ammo_label: return
	_ensure_info_container()
	
	ammo_label = Label.new()
	ammo_label.name = "AmmoLabel"
	ammo_label.text = "予備: --"
	ammo_label.add_theme_font_size_override("font_size", 12)
	ammo_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	_info_container.add_child(ammo_label)
	_info_container.move_child(ammo_label, 0)

func update_ammo(amount: int):
	create_ammo_label_if_needed()
	if ammo_label:
		ammo_label.text = "予備: %d" % amount

func create_weapon_label():
	_ensure_info_container()
	
	weapon_label = Label.new()
	weapon_label.name = "WeaponLabel"
	weapon_label.add_theme_font_size_override("font_size", 13)
	weapon_label.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25)) # Dull Gold
	weapon_label.text = ""
	_info_container.add_child(weapon_label)

func update_weapon_info(weapon_name: String, ammo: int, max_ammo: int, cooldown: int):
	if not weapon_label:
		create_weapon_label()
	
	if weapon_name == "":
		weapon_label.text = ""
		return

	var txt = weapon_name
	if max_ammo > 0:
		var shots_remaining = max_ammo - ammo
		txt += " [%d/%d]" % [shots_remaining, max_ammo]
	
	if cooldown > 0:
		txt += " (リロード中: %d)" % cooldown
	
	weapon_label.text = txt

# --- Shortcut Panel & Skill Bar ---

func create_skill_bar():
	# Outer background Panel Container
	shortcut_panel = PanelContainer.new()
	shortcut_panel.name = "ShortcutPanel"
	shortcut_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	shortcut_panel.offset_left = -540
	shortcut_panel.offset_top = -90
	shortcut_panel.offset_right = -20
	shortcut_panel.offset_bottom = -20
	shortcut_panel.add_theme_stylebox_override("panel", get_panel_style())
	add_child(shortcut_panel)
	
	skill_bar_container = HBoxContainer.new()
	skill_bar_container.name = "SkillBarContainer"
	skill_bar_container.add_theme_constant_override("separation", 6)
	skill_bar_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skill_bar_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shortcut_panel.add_child(skill_bar_container)
	
	# Initialize 9 slots
	for i in range(MAX_SKILL_SLOTS):
		var slot = _create_skill_slot(i + 1)
		skill_bar_container.add_child(slot)
		
	# Initial skill bar sync
	call_deferred("_initial_skill_update")

func _initial_skill_update():
	var player = get_tree().get_first_node_in_group("player")
	if player and "known_skills" in player and "skill_cooldowns" in player:
		update_skill_bar(player.known_skills, player.skill_cooldowns)
	else:
		update_skill_bar([], {})

func _create_skill_slot(key_num: int) -> Panel:
	var slot = Panel.new()
	slot.name = "Slot" + str(key_num)
	slot.custom_minimum_size = Vector2(50, 50)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.visible = true
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Initial stylebox
	slot.add_theme_stylebox_override("panel", get_slot_style(false, false))
	slot.set_meta("slot_index", key_num - 1)
	slot.gui_input.connect(_on_skill_slot_gui_input.bind(slot))
	_setup_slot_hover(slot)
	
	# Key indicator
	var key_label = Label.new()
	key_label.text = str(key_num)
	key_label.add_theme_font_size_override("font_size", 10)
	key_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	key_label.position = Vector2(3, 2)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(key_label)
	
	# Skill Name
	var name_label = Label.new()
	name_label.name = "SkillName"
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.offset_left = 2
	name_label.offset_top = 12
	name_label.offset_right = -2
	name_label.offset_bottom = -2
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.85))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(name_label)
	
	# CD Overlay
	var cd_overlay = ColorRect.new()
	cd_overlay.name = "CDOverlay"
	cd_overlay.color = Color(0, 0, 0, 0.6)
	cd_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd_overlay.visible = false
	cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(cd_overlay)
	
	var cd_label = Label.new()
	cd_label.name = "CDLabel"
	cd_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd_label.add_theme_font_size_override("font_size", 16)
	cd_label.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_overlay.add_child(cd_label)
	
	# Drop Highlight
	var drop_highlight = ColorRect.new()
	drop_highlight.name = "DropHighlight"
	drop_highlight.color = Color(0.85, 0.68, 0.25, 0.0) # Subtle gold glow
	drop_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	drop_highlight.visible = true
	drop_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(drop_highlight)
	
	return slot

func update_skill_bar(known_skills: Array, cooldowns: Dictionary):
	if not skill_bar_container: return
	var slots = skill_bar_container.get_children()
	if slots.size() != MAX_SKILL_SLOTS: return
		
	for i in range(MAX_SKILL_SLOTS):
		if i >= slots.size(): break
		var slot = slots[i]
		var name_label = slot.get_node_or_null("SkillName")
		var cd_overlay = slot.get_node_or_null("CDOverlay")
		if not name_label or not cd_overlay: continue
		var cd_label = cd_overlay.get_node_or_null("CDLabel")
		if not cd_label: continue
		
		var is_filled = i < known_skills.size()
		var is_selected = false
		if is_filled:
			var skill_id = known_skills[i]
			is_selected = (skill_id == _last_active_skill_id)
			var skill_data = SkillDatabase.get_skill_by_id(skill_id)
			
			if skill_data and skill_data.has("name"):
				var skill_name = skill_data.name
				if skill_name.length() > 3:
					name_label.text = skill_name.left(3)
				else:
					name_label.text = skill_name
			else:
				name_label.text = "???"
			
			if cooldowns.has(skill_id) and cooldowns[skill_id] > 0:
				cd_overlay.visible = true
				cd_label.text = str(cooldowns[skill_id])
			else:
				cd_overlay.visible = false
		else:
			name_label.text = ""
			cd_overlay.visible = false
			
		slot.add_theme_stylebox_override("panel", get_slot_style(is_filled, is_selected))

func _refresh_slot_borders():
	update_skill_bar([], {}) # Dummy update to force full redraw
	_initial_skill_update()

# --- Slot GUI & Drag-Drop Events ---

func _on_skill_slot_gui_input(event: InputEvent, slot: Panel):
	var slot_index = slot.get_meta("slot_index")
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var player = get_tree().get_first_node_in_group("player")
				if player and slot_index < player.known_skills.size():
					_pending_drag_slot = slot_index
					_pending_drag_skill = player.known_skills[slot_index]
					_drag_mouse_start = event.global_position
				else:
					_pending_drag_slot = -1
					_pending_drag_skill = ""
			else:
				if _drag_ghost and (_drag_source_slot >= 0 or _drag_from_menu):
					_try_drop_on_slot(slot_index)
				elif _pending_drag_slot >= 0 and _pending_drag_slot == slot_index:
					var slot_rect = Rect2(Vector2.ZERO, slot.size)
					if slot_rect.has_point(slot.get_local_mouse_position()):
						_activate_skill_by_slot(slot_index)
				_pending_drag_slot = -1
				_pending_drag_skill = ""
	
	elif event is InputEventMouseMotion:
		if _pending_drag_slot >= 0 and not _drag_ghost:
			var dist = event.global_position.distance_to(_drag_mouse_start)
			if dist >= DRAG_THRESHOLD:
				_start_drag_from_slot(_pending_drag_slot, _pending_drag_skill, false)
				_pending_drag_slot = -1
				_pending_drag_skill = ""

func _start_drag_from_slot(slot_index: int, skill_id: String, from_menu: bool):
	if skill_id == "": return
	_drag_source_slot = slot_index
	_drag_skill_id = skill_id
	_drag_from_menu = from_menu
	_create_drag_ghost(skill_id)

func start_drag_from_menu(skill_id: String):
	_drag_source_slot = -1
	_drag_skill_id = skill_id
	_drag_from_menu = true
	_create_drag_ghost(skill_id)

func _create_drag_ghost(skill_id: String):
	if _drag_ghost:
		_drag_ghost.queue_free()
		_drag_ghost = null
	
	var ghost = Panel.new()
	ghost.custom_minimum_size = Vector2(50, 50)
	ghost.size = Vector2(50, 50)
	ghost.modulate.a = 0.75
	ghost.z_index = 200
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var ghost_style = StyleBoxFlat.new()
	ghost_style.bg_color = Color(0.12, 0.12, 0.15, 0.85)
	ghost_style.set_border_width_all(1)
	ghost_style.border_color = Color(0.85, 0.68, 0.25, 1.0)
	ghost_style.set_corner_radius_all(3)
	ghost.add_theme_stylebox_override("panel", ghost_style)
	
	var skill_data = SkillDatabase.get_skill_by_id(skill_id)
	var ghost_label = Label.new()
	ghost_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	ghost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ghost_label.add_theme_font_size_override("font_size", 11)
	ghost_label.add_theme_color_override("font_color", Color.WHITE)
	ghost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if skill_data and skill_data.has("name"):
		var n = skill_data.name
		ghost_label.text = n.left(3) if n.length() > 3 else n
	else:
		ghost_label.text = "???"
	ghost.add_child(ghost_label)
	
	ghost.global_position = get_viewport().get_mouse_position() - Vector2(25, 25)
	add_child(ghost)
	_drag_ghost = ghost

func _try_drop_on_slot(target_index: int):
	if _drag_ghost:
		_drag_ghost.queue_free()
		_drag_ghost = null
	
	_clear_drop_highlights()
	
	var player = get_tree().get_first_node_in_group("player")
	if not player or not "base_known_skills" in player:
		_reset_drag_state()
		return
	
	var skills = player.base_known_skills
	
	if _drag_from_menu and _drag_source_slot < 0:
		var skill_id = _drag_skill_id
		if skill_id == "":
			_reset_drag_state()
			return
		
		var existing_index = skills.find(skill_id)
		if existing_index >= 0:
			skills.remove_at(existing_index)
			var insert_at = min(target_index, skills.size())
			skills.insert(insert_at, skill_id)
		else:
			var insert_at = min(target_index, skills.size())
			skills.insert(insert_at, skill_id)
		
		player.base_known_skills = skills
		player._update_known_skills()
	
	elif _drag_source_slot >= 0 and _drag_source_slot != target_index:
		if _drag_source_slot < skills.size() and target_index <= skills.size():
			var skill_id = skills[_drag_source_slot]
			skills.remove_at(_drag_source_slot)
			var insert_at = min(target_index, skills.size())
			if target_index > _drag_source_slot:
				insert_at = min(target_index - 1, skills.size())
			skills.insert(insert_at, skill_id)
			player.base_known_skills = skills
			player._update_known_skills()
	
	_reset_drag_state()

func _reset_drag_state():
	_drag_source_slot = -1
	_drag_skill_id = ""
	_drag_from_menu = false
	if _drag_ghost:
		_drag_ghost.queue_free()
		_drag_ghost = null

func _clear_drop_highlights():
	if not skill_bar_container: return
	for slot in skill_bar_container.get_children():
		var hl = slot.get_node_or_null("DropHighlight")
		if hl:
			hl.color = Color(0.85, 0.68, 0.25, 0.0)

func _input(event: InputEvent):
	if event is InputEventMouseMotion:
		if _drag_ghost and (_drag_source_slot >= 0 or _drag_from_menu):
			_drag_ghost.global_position = event.global_position - Vector2(25, 25)
			_update_drop_highlights(event.global_position)
		
		if _pending_drag_slot >= 0 and not _drag_ghost:
			var dist = event.global_position.distance_to(_drag_mouse_start)
			if dist >= DRAG_THRESHOLD:
				_start_drag_from_slot(_pending_drag_slot, _pending_drag_skill, false)
				_pending_drag_slot = -1
				_pending_drag_skill = ""
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _drag_ghost and (_drag_source_slot >= 0 or _drag_from_menu):
			var dropped_on_slot = false
			if skill_bar_container:
				for slot in skill_bar_container.get_children():
					var slot_rect = Rect2(slot.global_position, slot.size)
					if slot_rect.has_point(event.global_position):
						dropped_on_slot = true
						_try_drop_on_slot(slot.get_meta("slot_index"))
						break
			
			if not dropped_on_slot:
				_reset_drag_state()
				_clear_drop_highlights()

func _update_drop_highlights(mouse_pos: Vector2):
	if not skill_bar_container: return
	if not (_drag_source_slot >= 0 or _drag_from_menu): return
	
	for slot in skill_bar_container.get_children():
		var hl = slot.get_node_or_null("DropHighlight")
		if not hl: continue
		var slot_rect = Rect2(slot.global_position, slot.size)
		if slot_rect.has_point(mouse_pos):
			hl.color = Color(0.85, 0.68, 0.25, 0.35)
		else:
			hl.color = Color(0.85, 0.68, 0.25, 0.0)

func _setup_slot_hover(slot: Panel):
	slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
	slot.mouse_exited.connect(_on_slot_mouse_exited.bind(slot))

func _on_slot_mouse_entered(slot: Panel):
	if _drag_source_slot >= 0 or _drag_from_menu: return
	var style = slot.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var hover_style = style.duplicate()
		hover_style.border_color = Color(0.85, 0.68, 0.25, 0.8) # Dull gold hover
		hover_style.set_border_width_all(1)
		slot.add_theme_stylebox_override("panel", hover_style)

func _on_slot_mouse_exited(slot: Panel):
	var slot_index = slot.get_meta("slot_index")
	var player = get_tree().get_first_node_in_group("player")
	var is_filled = false
	if player and "known_skills" in player:
		is_filled = slot_index < player.known_skills.size()
	var is_selected = false
	if is_filled:
		var skill_id = player.known_skills[slot_index]
		is_selected = (skill_id == _last_active_skill_id)
	slot.add_theme_stylebox_override("panel", get_slot_style(is_filled, is_selected))

func _activate_skill_by_slot(slot_index: int):
	var player = get_tree().get_first_node_in_group("player")
	if not player or not "known_skills" in player: return
	
	var known_skills = player.known_skills
	if slot_index >= 0 and slot_index < known_skills.size():
		var skill_id = known_skills[slot_index]
		if player.has_method("use_skill"):
			player.use_skill(skill_id)
