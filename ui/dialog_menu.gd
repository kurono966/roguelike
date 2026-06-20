extends Control

signal option_selected(option: String)

var options: Array = []
var option_buttons: Array = []

func _ready():
	hide()
	# Get predefined option buttons (if any)
	for child in $Panel/VBoxContainer/OptionsContainer.get_children():
		if child is Button:
			option_buttons.append(child)
			child.pressed.connect(_on_option_pressed.bind(child.text))
			child.focus_entered.connect(func(): child.modulate = Color(1.2, 1.2, 1.2))
			child.focus_exited.connect(func(): child.modulate = Color(1, 1, 1))

func show_dialog(title: String, dialog_options: Array):
	$Panel/VBoxContainer/TitleLabel.autowrap_mode = 2 # AUTOWRAP_WORD_SMART
	$Panel/VBoxContainer/TitleLabel.text = title
	options = dialog_options
	
	# Clear existing buttons
	for child in $Panel/VBoxContainer/OptionsContainer.get_children():
		child.queue_free()
	option_buttons.clear()
	
	# Create new buttons
	for option in options:
		var button = Button.new()
		button.text = option
		button.pressed.connect(_on_option_pressed.bind(option))
		button.focus_entered.connect(func(): button.modulate = Color(1.2, 1.2, 1.2))
		button.focus_exited.connect(func(): button.modulate = Color(1, 1, 1))
		$Panel/VBoxContainer/OptionsContainer.add_child(button)
		option_buttons.append(button)
	
	show()
	
	# Focus the first option
	if not option_buttons.is_empty():
		option_buttons[0].grab_focus()

func _input(event):
	if not visible:
		return
	
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		hide()
		option_selected.emit("キャンセル")
		get_viewport().set_input_as_handled()

func _on_option_pressed(option: String):
	hide()
	option_selected.emit(option)

