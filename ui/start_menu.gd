extends Control

func _ready():
	# Focus the new game button for keyboard navigation support
	$Panel/VBoxContainer/QuickStartButton.grab_focus()

func _on_quick_start_pressed():
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.detailed_character_creation = false
	if get_tree():
		get_tree().change_scene_to_file("res://ui/character_creation.tscn")

func _on_character_create_pressed():
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.detailed_character_creation = true
	if get_tree():
		get_tree().change_scene_to_file("res://ui/character_creation.tscn")

func _on_quit_pressed():
	if get_tree():
		get_tree().quit()
