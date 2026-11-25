extends Node3D
## Cat Run — prototype runner.
## Everything is built in code so the project opens cleanly on any Godot 4 editor.
## Drop your own models into res://assets/ with these names and they replace the placeholders:
##   cat.glb            player (needs animations: Run, Jump, Slide, Idle)
##   fish.glb           collectible fish
##   obstacle_low.glb   jump-over barrier   (~2m wide, ~1m tall)
##   obstacle_high.glb  slide-under bar     (~2m wide, bar from 1.2m up)
##   obstacle_full.glb  block / truck / train (~2m wide, ~3m tall, 8m long, front at z=0, extends to -Z)
##   segment.glb        one 40m piece of street (road + sidewalks + walls), front at z=0, extends to -Z

const LANE_W := 2.2
const SEG_LEN := 40.0
const SEG_COUNT := 6
const ASSET_DIR := "res://assets/"
const GRAVITY := 40.0
const JUMP_V := 13.5
const SLIDE_TIME := 0.75

const START_SPEED := 13.0
const MAX_SPEED := 30.0
const ACCEL := 0.22

var speed := START_SPEED
var running := false
var dead := false
var distance := 0.0
var fish_count := 0
var best := 0

var player: Node3D
var cat_model: Node3D
var anim: AnimationPlayer
var cam: Camera3D
var lane := 0
var py := 0.0
var vy := 0.0
var slide_t := 0.0

var segments: Array = []
var next_seg_z := 0.0
var obstacles: Array = []   # {node, x, z, len, kind}
var fishes: Array = []      # {node, x, z, y}
var next_row_z := -35.0
var rng := RandomNumberGenerator.new()
var mats := {}
var scenes := {}

var lbl_score: Label
var lbl_fish: Label
var lbl_best: Label
var start_panel: Control
var over_panel: Control
var lbl_over: Label
var touch_start := Vector2.ZERO
var touching := false
var swiped := false


func _ready() -> void:
	rng.randomize()
	_load_best()
	for n in ["cat.glb", "fish.glb", "obstacle_low.glb", "obstacle_high.glb", "obstacle_full.glb", "segment.glb"]:
		var p := ASSET_DIR + n
		scenes[n] = load(p) if ResourceLoader.exists(p) else null
	_setup_environment()
	_setup_player()
	_setup_camera()
	for i in SEG_COUNT:
		_spawn_segment()
	_setup_ui()
	_play("Idle", 0.0)


# ---------------------------------------------------------------- helpers
func _mat(c: Color, rough := 0.85, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s_%s" % [c.to_html(), rough, metal, emit]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rough := 0.85) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(c, rough)
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _instance(name: String) -> Node3D:
	if scenes.get(name) != null:
		return scenes[name].instantiate()
	return null


# ---------------------------------------------------------------- world
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.52, 0.93)
	sm.sky_horizon_color = Color(0.72, 0.87, 0.98)
	sm.ground_horizon_color = Color(0.72, 0.87, 0.98)
	sm.ground_bottom_color = Color(0.35, 0.4, 0.48)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.88, 0.98)
	env.fog_density = 0.006
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 28, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55.0
	add_child(sun)


func _spawn_segment() -> void:
	var seg := Node3D.new()
	seg.position.z = next_seg_z
	add_child(seg)
	var custom := _instance("segment.glb")
	if custom:
		seg.add_child(custom)
	else:
		var half := SEG_LEN / 2.0
		var road_w := LANE_W * 3.0 + 0.6
		_box(seg, Vector3(road_w, 0.2, SEG_LEN), Vector3(0, -0.1, -half), Color(0.33, 0.35, 0.39))
		for x in [-LANE_W / 2.0, LANE_W / 2.0]:
			for k in 10:
				_box(seg, Vector3(0.12, 0.02, 1.8), Vector3(x, 0.01, -2.0 - k * 4.0), Color(0.85, 0.86, 0.88))
		for s in [-1, 1]:
			var sx: float = s * (road_w / 2.0 + 1.1)
			_box(seg, Vector3(2.2, 0.3, SEG_LEN), Vector3(sx, 0.15, -half), Color(0.6, 0.62, 0.67))
			var wx: float = s * (road_w / 2.0 + 2.5)
			_box(seg, Vector3(0.6, 6.0, SEG_LEN), Vector3(wx, 3.0, -half), Color(0.7, 0.34, 0.23))
			for k in 4:
				_box(seg, Vector3(1.0, 6.6, 1.0), Vector3(wx - s * 0.2, 3.3, -5.0 - k * 10.0), Color(0.82, 0.79, 0.73))
			if rng.randf() < 0.7:
				var bz := -rng.randf_range(4.0, SEG_LEN - 4.0)
				var bin := _box(seg, Vector3(1.0, 1.3, 1.0), Vector3(sx, 0.95, bz), Color(0.45, 0.5, 0.56), 0.5)
				_box(bin, Vector3(1.1, 0.12, 1.1), Vector3(0, 0.7, 0), Color(0.36, 0.4, 0.46), 0.5)
	segments.append(seg)
	next_seg_z -= SEG_LEN


func _recycle_segments() -> void:
	for seg in segments:
		if seg.position.z - SEG_LEN > player.position.z + 25.0:
			seg.position.z = next_seg_z
			next_seg_z -= SEG_LEN


# ---------------------------------------------------------------- player
func _setup_player() -> void:
	player = Node3D.new()
	add_child(player)
	cat_model = _instance("cat.glb")
	if cat_model:
		cat_model.rotation_degrees.y = 180.0
		cat_model.scale = Vector3.ONE * 1.15
		player.add_child(cat_model)
		var found := cat_model.find_children("*", "AnimationPlayer", true, false)
		if found.size() > 0:
			anim = found[0]
			for n in anim.get_animation_list():
				if n.ends_with("Run") or n.ends_with("Idle"):
					anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	else:
		cat_model = Node3D.new()
		player.add_child(cat_model)
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.4
		cap.height = 1.6
		cap.material = _mat(Color(1.0, 0.5, 0.1))
		body.mesh = cap
		body.position.y = 0.8
		cat_model.add_child(body)


func _anim_name(base: String) -> String:
	if anim == null:
		return ""
	for n in anim.get_animation_list():
		if n == base or n.ends_with("/" + base) or n.to_lower() == base.to_lower():
			return n
	return ""


func _play(base: String, blend := 0.15, spd := 1.0) -> void:
	var n := _anim_name(base)
	if n != "":
		anim.play(n, blend, spd)


func _setup_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 260.0
	add_child(cam)
	_update_camera(1.0)


func _update_camera(t: float) -> void:
	var target := Vector3(player.position.x * 0.6, 4.1 + py * 0.35, player.position.z + 6.2)
	cam.position = cam.position.lerp(target, t)
	cam.look_at(Vector3(player.position.x * 0.4, 1.3, player.position.z - 9.0), Vector3.UP)


# ---------------------------------------------------------------- controls
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			touching = true
			swiped = false
			touch_start = e.position
			if not running and not dead:
				_start_game()
		else:
			touching = false
	elif e is InputEventScreenDrag and touching and not swiped:
		var d: Vector2 = e.position - touch_start
		if d.length() > 45.0:
			swiped = true
			if absf(d.x) > absf(d.y):
				_change_lane(1 if d.x > 0 else -1)
			elif d.y < 0:
				_jump()
			else:
				_slide()
	elif e is InputEventKey and e.pressed and not e.echo:
		if not running and not dead:
			_start_game()
			return
		match e.keycode:
			KEY_LEFT, KEY_A:
				_change_lane(-1)
			KEY_RIGHT, KEY_D:
				_change_lane(1)
			KEY_UP, KEY_W, KEY_SPACE:
				_jump()
			KEY_DOWN, KEY_S:
				_slide()


func _change_lane(dir: int) -> void:
	if not running:
		return
	lane = clampi(lane + dir, -1, 1)


func _jump() -> void:
	if not running or py > 0.05:
		return
	vy = JUMP_V
	slide_t = 0.0
	_play("Jump", 0.08, 1.15)


func _slide() -> void:
	if not running:
		return
	if py > 0.05:
		vy = -JUMP_V * 1.6   # fast fall, then slide
	slide_t = SLIDE_TIME
	_play("Slide", 0.08)


func _start_game() -> void:
	running = true
	start_panel.visible = false
	_play("Run", 0.2)


# ---------------------------------------------------------------- spawning
func _spawn_rows() -> void:
	while next_row_z > player.position.z - 130.0:
		_spawn_row(next_row_z)
		next_row_z -= rng.randf_range(16.0, 24.0) * clampf(speed / START_SPEED, 1.0, 1.6)


func _spawn_row(z: float) -> void:
	var kinds := []
	for l in 3:
		var r := rng.randf()
		if r < 0.38:
			kinds.append("none")
		elif r < 0.58:
			kinds.append("low")
		elif r < 0.74:
			kinds.append("high")
		else:
			kinds.append("full")
	if not kinds.has("none") and kinds.count("full") >= 2:
		kinds[rng.randi_range(0, 2)] = "none"
	if kinds.count("full") == 3:
		kinds[1] = "low"
	for l in 3:
		var x := (l - 1) * LANE_W
		match kinds[l]:
			"low":
				_add_obstacle("low", x, z)
				_add_fish_arc(x, z)
			"high":
				_add_obstacle("high", x, z)
			"full":
				_add_obstacle("full", x, z)
			"none":
				if rng.randf() < 0.55:
					_add_fish_line(x, z + 4.0, 6)


func _add_obstacle(kind: String, x: float, z: float) -> void:
	var n := Node3D.new()
	n.position = Vector3(x, 0, z)
	add_child(n)
	var length := 0.5
	var custom := _instance("obstacle_%s.glb" % kind)
	if custom:
		n.add_child(custom)
		if kind == "full":
			length = 8.0
	else:
		match kind:
			"low":
				for px in [-0.85, 0.85]:
					_box(n, Vector3(0.14, 1.0, 0.14), Vector3(px, 0.5, 0), Color(0.9, 0.9, 0.9))
				for k in 5:
					_box(n, Vector3(0.36, 0.34, 0.12), Vector3(-0.8 + k * 0.4, 0.8, 0), Color(0.9, 0.15, 0.15) if k % 2 == 0 else Color(1, 1, 1), 0.5)
			"high":
				for px in [-0.95, 0.95]:
					_box(n, Vector3(0.16, 2.4, 0.16), Vector3(px, 1.2, 0), Color(0.95, 0.75, 0.1), 0.5)
				_box(n, Vector3(2.0, 0.7, 0.2), Vector3(0, 1.85, 0), Color(0.95, 0.75, 0.1), 0.5)
				_box(n, Vector3(1.6, 0.25, 0.22), Vector3(0, 1.85, 0), Color(0.15, 0.15, 0.15))
			"full":
				length = 8.0
				var c := [Color(0.2, 0.45, 0.85), Color(0.85, 0.25, 0.2), Color(0.2, 0.6, 0.35)][rng.randi_range(0, 2)]
				_box(n, Vector3(2.0, 2.8, length), Vector3(0, 1.6, -length / 2.0), c, 0.45)
				_box(n, Vector3(1.6, 0.9, 0.05), Vector3(0, 2.2, 0.01), Color(0.6, 0.85, 1.0), 0.15)
				for wz in [-1.5, -6.5]:
					for wx in [-0.9, 0.9]:
						var w := MeshInstance3D.new()
						var cy := CylinderMesh.new()
						cy.top_radius = 0.38
						cy.bottom_radius = 0.38
						cy.height = 0.3
						cy.material = _mat(Color(0.08, 0.08, 0.08))
						w.mesh = cy
						w.rotation_degrees.z = 90
						w.position = Vector3(wx, 0.38, wz)
						n.add_child(w)
	obstacles.append({"node": n, "x": x, "z": z, "len": length, "kind": kind})


func _make_fish() -> Node3D:
	var custom := _instance("fish.glb")
	if custom:
		return custom
	var f := Node3D.new()
	var body := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.3
	sp.height = 0.6
	sp.material = _mat(Color(1.0, 0.68, 0.1), 0.3, 0.3, 0.35)
	body.mesh = sp
	body.scale = Vector3(1.2, 0.75, 0.45)
	f.add_child(body)
	var tail := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.45, 0.4, 0.08)
	pm.material = sp.material
	tail.mesh = pm
	tail.rotation_degrees.z = 90
	tail.position.x = 0.45
	f.add_child(tail)
	return f


func _add_fish(x: float, y: float, z: float) -> void:
	var f := _make_fish()
	f.position = Vector3(x, y, z)
	add_child(f)
	fishes.append({"node": f, "x": x, "z": z, "y": y})


func _add_fish_line(x: float, z: float, count: int) -> void:
	for i in count:
		_add_fish(x, 0.7, z - i * 2.0)


func _add_fish_arc(x: float, z: float) -> void:
	for i in 5:
		var t := float(i) / 4.0
		_add_fish(x, 0.8 + sin(t * PI) * 2.0, z + 4.0 - i * 2.0)


# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	for f in fishes:
		f.node.rotate_y(delta * 3.0)
	if not running:
		if not dead:
			_update_camera(1.0)
		return

	speed = minf(MAX_SPEED, speed + ACCEL * delta)
	var step := speed * delta
	player.position.z -= step
	distance += step

	# lanes
	var tx := lane * LANE_W
	var prev_x := player.position.x
	player.position.x = lerpf(player.position.x, tx, clampf(delta * 14.0, 0.0, 1.0))
	cat_model.rotation.z = clampf((player.position.x - prev_x) / maxf(delta, 0.001) * -0.012, -0.35, 0.35)

	# jump / slide
	if py > 0.0 or vy > 0.0:
		vy -= GRAVITY * delta
		py += vy * delta
		if py <= 0.0:
			py = 0.0
			vy = 0.0
			if slide_t <= 0.0:
				_play("Run", 0.12)
	if slide_t > 0.0:
		slide_t -= delta
		if slide_t <= 0.0 and py <= 0.0:
			_play("Run", 0.15)
	player.position.y = py

	_recycle_segments()
	_spawn_rows()
	_check_hits()
	_update_camera(clampf(delta * 8.0, 0.0, 1.0))
	lbl_score.text = "%d m" % int(distance)
	lbl_fish.text = "FISH  %d" % fish_count


func _check_hits() -> void:
	var px := player.position.x
	var pz := player.position.z
	for o in obstacles:
		if absf(o.x - px) > 1.0:
			continue
		var zmax: float = o.z + 0.3
		var zmin: float = o.z - o.len - 0.3
		if pz - 0.3 < zmax and pz + 0.3 > zmin:
			var hit := false
			match o.kind:
				"low":
					hit = py < 0.95
				"high":
					hit = slide_t <= 0.0 or py > 0.5
				"full":
					hit = true
			if hit:
				_die()
				return
	var keep := []
	for f in fishes:
		var fn: Node3D = f.node
		if absf(f.x - px) < 1.0 and absf(f.z - pz) < 1.0 and absf(f.y - (py + 0.8)) < 1.3:
			fish_count += 1
			fn.queue_free()
		elif f.z > pz + 12.0:
			fn.queue_free()
		else:
			keep.append(f)
	fishes = keep
	var keep_o := []
	for o in obstacles:
		if o.z - o.len > pz + 12.0:
			o.node.queue_free()
		else:
			keep_o.append(o)
	obstacles = keep_o


func _die() -> void:
	running = false
	dead = true
	if anim:
		anim.pause()
	var tw := create_tween()
	tw.tween_property(cat_model, "rotation:x", -1.4, 0.35)
	tw.parallel().tween_property(player, "position:z", player.position.z + 1.2, 0.35)
	var score := int(distance) + fish_count * 10
	if score > best:
		best = score
		_save_best()
	lbl_over.text = "GAME OVER\n\nDistance  %d m\nFish  %d\nScore  %d\nBest  %d" % [int(distance), fish_count, score, best]
	await get_tree().create_timer(0.7).timeout
	over_panel.visible = true


# ---------------------------------------------------------------- UI
func _label(text: String, size: int, parent: Control) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	lbl_score = _label("0 m", 40, root)
	lbl_score.position = Vector2(30, 40)
	lbl_fish = _label("FISH  0", 40, root)
	lbl_fish.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lbl_fish.position = Vector2(-260, 40)
	lbl_fish.size = Vector2(230, 60)
	lbl_fish.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	start_panel = Control.new()
	start_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	start_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(start_panel)
	var title := _label("CAT RUN", 96, start_panel)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(700, 140)
	title.position = Vector2(-350, 220)
	var hint := _label("Tap to start\n\nSwipe left / right  -  lane\nSwipe up  -  jump\nSwipe down  -  slide", 34, start_panel)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(700, 320)
	hint.position = Vector2(-350, -380)
	lbl_best = _label("BEST  %d" % best, 36, start_panel)
	lbl_best.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_best.size = Vector2(700, 60)
	lbl_best.position = Vector2(-350, 360)

	over_panel = ColorRect.new()
	(over_panel as ColorRect).color = Color(0.03, 0.05, 0.12, 0.72)
	over_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_panel.visible = false
	root.add_child(over_panel)
	lbl_over = _label("", 52, over_panel)
	lbl_over.set_anchors_preset(Control.PRESET_CENTER)
	lbl_over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_over.size = Vector2(700, 520)
	lbl_over.position = Vector2(-350, -400)
	var btn := Button.new()
	btn.text = "PLAY AGAIN"
	btn.add_theme_font_size_override("font_size", 44)
	btn.set_anchors_preset(Control.PRESET_CENTER)
	btn.size = Vector2(420, 110)
	btn.position = Vector2(-210, 180)
	btn.pressed.connect(func(): get_tree().reload_current_scene())
	over_panel.add_child(btn)


# ---------------------------------------------------------------- save
func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://save.cfg") == OK:
		best = int(cf.get_value("game", "best", 0))


func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "best", best)
	cf.save("user://save.cfg")
