extends SceneTree
## Renders the game for a few seconds and saves screenshots to res://shots/
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	root.size = Vector2i(720, 1280)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30: await process_frame
	_save("res://shots/1_start.png")
	main._start_game()
	main.ACCEL
	for i in 150:
		# dodge automatically so we keep running
		for o in main.obstacles:
			var dz = main.player.position.z - o.z
			if dz > 0 and dz < 6 and absf(o.x - main.player.position.x) < 1.0:
				if o.kind == "low": main._jump()
				elif o.kind == "high": main._slide()
				else: main._change_lane(1 if main.lane < 1 else -1)
		if i == 60: _save("res://shots/2_run.png")
		await process_frame
	main._jump()
	for i in 8: await process_frame
	_save("res://shots/3_jump.png")
	main._die()
	for i in 60: await process_frame
	_save("res://shots/4_over.png")
	print("SHOT_OK dead=", main.dead, " dist=", main.distance)
	quit(0)

func _save(p: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(p)
