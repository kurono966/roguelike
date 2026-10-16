extends SceneTree

func _initialize():
	call_deferred("_run")

func _run():
	var scene = load("res://actors/enemy/enemy.tscn")
	var npc = scene.instantiate()
	npc.is_npc = true
	root.add_child(npc)
	assert(npc._get_ascii_char() == "@", "Neutral NPC must retain @")
	npc._make_hostile()
	assert(npc._get_ascii_char() == "hostile_npc", "Hostile NPC must have horns")
	var angry_image = npc.get_node("Sprite2D").texture.get_image()
	var restored = scene.instantiate()
	restored.is_hostile_to_player_only = true
	restored.base_color = Color.GREEN
	root.add_child(restored)
	assert(restored.get_node("Sprite2D").texture.get_image().get_data() == angry_image.get_data(), "Restored hostility must retain appearance")
	var preview = Image.create(64, 32, false, Image.FORMAT_RGBA8)
	var neutral = AsciiArtGenerator.create_ascii_sprite("@", Color(0.5, 0.9, 0.5)).get_image()
	preview.blit_rect(neutral, Rect2i(0, 0, 32, 32), Vector2i.ZERO)
	preview.blit_rect(angry_image, Rect2i(0, 0, 32, 32), Vector2i(32, 0))
	preview.resize(512, 256, Image.INTERPOLATE_NEAREST)
	preview.save_png("res://workdesk/hostile_npc_preview.png")
	print("HOSTILE_NPC_VISUAL_TEST passed")
	quit()
