extends Node3D
## WINDRUN orchestration: world, third-person camera, checkpoint trial, and UI.

const WorldScript = preload("res://scripts/world.gd")
const RunnerScript = preload("res://scripts/runner.gd")
const LandmarkScript = preload("res://scripts/landmarks.gd")
const SAVE_PATH := "user://windrun_records.json"

var meadow: MeadowWorld
var runner: WindRunner
var landmarks: WindLandmarks
var camera: Camera3D
var camera_yaw := 0.0
var camera_pitch := 0.32
var camera_position_initialized := false
var started := false
var paused := false
var zen_mode := false
var trial_active := false
var trial_finished := false
var elapsed := 0.0
var best_time := -1.0
var active_gate := 0
var gate_positions: Array[Vector2] = [
	Vector2(75, -75), Vector2(160, -145), Vector2(270, -125),
	Vector2(352, -228), Vector2(420, -355)
]
var gates: Array[Area3D] = []
var gate_visuals: Array[MeshInstance3D] = []
var marker_materials: Array[StandardMaterial3D] = []

var ui_layer: CanvasLayer
var speed_label: Label
var distance_label: Label
var mission_label: Label
var direction_label: Label
var hint_label: Label
var input_debug_label: Label
var last_key_received := "(none)"
var overlay: Control
var opening_art: TextureRect
var overlay_title: Label
var overlay_subtitle: Label
var overlay_instructions: Label
var wind_audio: AudioStreamPlayer
var nature_audio: AudioStreamPlayer
var music_audio: AudioStreamPlayer
var music_enabled := true
var music_volume_adjust_db := 0.0
var music_notice_label: Label
var music_notice_timer := 0.0
var step_audios: Array[AudioStreamPlayer] = []
var step_sound_cooldown := 0.0
var last_footstep_index := -1
var footstep_rng := RandomNumberGenerator.new()
var jump_audio: AudioStreamPlayer
var land_audio: AudioStreamPlayer
var running_dust: CPUParticles3D
var landing_dust: CPUParticles3D
var camera_land_kick := 0.0
var camera_launch_kick := 0.0
var camera_bank := 0.0
var hud_visible := true
var debug_visible := false
var hud_root: Control
var discoveries_label: Label
var discovery_flash: Label
var discovery_flash_timer := 0.0
var discovery_audio: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	footstep_rng.randomize()
	_configure_controls()
	meadow = WorldScript.new() as MeadowWorld
	meadow.name = "The_Living_Meadow"
	add_child(meadow)
	landmarks = LandmarkScript.new() as WindLandmarks
	landmarks.world = meadow
	add_child(landmarks)
	runner = RunnerScript.new() as WindRunner
	runner.world = meadow
	add_child(runner)
	runner.reset_runner()
	runner.can_move = false
	runner.jumped.connect(_on_runner_jump)
	runner.landed.connect(_on_runner_land)
	runner.stepped.connect(_on_runner_step)
	camera = Camera3D.new()
	camera.name = "Speed_follow_camera"
	camera.current = true
	camera.far = 1900.0
	camera.near = 0.08
	add_child(camera)
	_build_hud()
	_build_motion_fx()
	_build_course()
	_load_records()
	if ResourceLoader.exists("res://assets/wind.wav"):
		wind_audio = AudioStreamPlayer.new()
		wind_audio.stream = load("res://assets/wind.wav")
		wind_audio.volume_db = -32.0
		add_child(wind_audio)
		wind_audio.play()
	_setup_sounds()
	music_audio = _create_sound_player("res://assets/meadow_theme.wav", -8.0)
	if music_audio != null:
		# Keep the gentle soundtrack going behind menus and pause screens.
		music_audio.process_mode = Node.PROCESS_MODE_ALWAYS
		if music_audio.stream is AudioStreamWAV:
			(music_audio.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		music_audio.play()
	discovery_audio = _create_sound_player("res://assets/discovery.wav", -20.0)
	_load_discoveries()
	_show_start_screen()
	# Once every system has initialized, remove the built-in visible startup fallback.
	var fallback := get_node_or_null("Startup_fallback")
	if fallback != null:
		fallback.queue_free()


func _configure_controls() -> void:
	# Register named actions rather than requiring an exact OS keyboard layout.
	_bind_key_action("wind_forward", [KEY_W, KEY_UP])
	_bind_key_action("wind_backward", [KEY_S, KEY_DOWN])
	_bind_key_action("wind_left", [KEY_A, KEY_LEFT])
	_bind_key_action("wind_right", [KEY_D, KEY_RIGHT])
	_bind_key_action("wind_jump", [KEY_SPACE])
	_bind_key_action("wind_sprint", [KEY_SHIFT])
	_bind_key_action("wind_brake", [KEY_CTRL])

func _bind_key_action(action_name: StringName, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for key in keys:
		var physical_event := InputEventKey.new()
		physical_event.physical_keycode = key
		InputMap.action_add_event(action_name, physical_event)
		# Also recognize the logical key (e.g. in virtualized input contexts).
		var logical_event := InputEventKey.new()
		logical_event.keycode = key
		InputMap.action_add_event(action_name, logical_event)

func _build_course() -> void:
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 4.45
	ring_mesh.outer_radius = 4.8
	ring_mesh.rings = 36
	ring_mesh.ring_segments = 9
	for i in range(gate_positions.size()):
		var coords := gate_positions[i]
		var gate := Area3D.new()
		gate.name = "Wind_gate_%d" % (i + 1)
		gate.position = Vector3(coords.x, meadow.height_at(coords.x, coords.y) + 5.5, coords.y)
		gate.monitoring = true
		gate.monitorable = true
		add_child(gate)
		var sphere := SphereShape3D.new()
		sphere.radius = 6.3
		var hitbox := CollisionShape3D.new()
		hitbox.shape = sphere
		gate.add_child(hitbox)
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.rotation_degrees.x = 90.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("56d6b9")
		mat.emission_enabled = true
		mat.emission = Color("39cbaa")
		mat.emission_energy_multiplier = 0.65
		mat.metallic = 0.15
		ring.material_override = mat
		gate.add_child(ring)
		var beacon := MeshInstance3D.new()
		var beacon_mesh := SphereMesh.new()
		beacon_mesh.radius = 1.1
		beacon_mesh.height = 2.2
		beacon.mesh = beacon_mesh
		beacon.material_override = mat
		beacon.position = Vector3(0, 6.6, 0)
		gate.add_child(beacon)
		gate.body_entered.connect(_checkpoint_hit.bind(i))
		gates.append(gate)
		gate_visuals.append(ring)
		marker_materials.append(mat)
	_update_gate_appearance()

func _checkpoint_hit(body: Node3D, index: int) -> void:
	if not started or zen_mode or body != runner or index != active_gate or trial_finished:
		return
	if index == 0:
		trial_active = true
		elapsed = 0.0
	active_gate += 1
	if active_gate >= gates.size():
		trial_active = false
		trial_finished = true
		if best_time < 0.0 or elapsed < best_time:
			best_time = elapsed
			_save_records()
		_show_status("COURSE COMPLETE  •  %.2f s" % elapsed)
	else:
		_show_status("GATE %d / %d" % [active_gate, gates.size()])
	_update_gate_appearance()

func _update_gate_appearance() -> void:
	for i in range(marker_materials.size()):
		var m := marker_materials[i]
		if i == active_gate and not trial_finished:
			m.albedo_color = Color("ffd45d")
			m.emission = Color("ffac33")
			m.emission_energy_multiplier = 1.6
		else:
			m.albedo_color = Color("5ac7a9")
			m.emission = Color("309d83")
			m.emission_energy_multiplier = 0.25

func _build_hud() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 3
	add_child(ui_layer)
	var hud := Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(hud)
	hud_root = hud
	speed_label = _make_label(hud, Vector2(30, 23), 40, "000", Color("f9fff1"))
	distance_label = _make_label(hud, Vector2(32, 78), 14, "km/h   •   0 m travelled", Color("e4f7e9"))
	mission_label = _make_label(hud, Vector2(30, 115), 19, "GATE 1 / 5", Color("ffecad"))
	direction_label = _make_label(hud, Vector2(30, 144), 15, "Follow the golden ring", Color("f4ffe8"))
	hint_label = _make_label(hud, Vector2(30, 664), 14,
		"WASD MOVE    SHIFT SPRINT    SPACE JUMP    G SUNSET    M MUSIC    V VEGETATION    H HUD", Color("ffffff"))
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_label.position = Vector2(30, -45)
	discoveries_label = _make_label(hud, Vector2(30, 175), 15, "DISCOVERIES 0 / 3", Color("fff2be"))
	discovery_flash = _make_label(hud, Vector2(0, 250), 27, "", Color("fff0bb"))
	discovery_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	discovery_flash.position = Vector2(-220, 225)
	discovery_flash.size = Vector2(440, 70)
	discovery_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discovery_flash.visible = false
	input_debug_label = _make_label(hud, Vector2(30, 209), 14, "KEYBOARD READY", Color("ffffff"))
	input_debug_label.visible = debug_visible
	music_notice_label = _make_label(hud, Vector2(30, 238), 15, "", Color("f6ffe2"))
	music_notice_label.visible = false
	# Fullscreen menu scrim + centered intro, used for pause as well.
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(overlay)
	# Illustrated menu concept art; actual gameplay remains fully realtime 3D.
	opening_art = TextureRect.new()
	opening_art.texture = load("res://assets/windrun_title_art.jpg")
	opening_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	opening_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	opening_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	opening_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(opening_art)
	var scrim := ColorRect.new()
	scrim.color = Color(0.025, 0.10, 0.13, 0.50)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(scrim)
	var centered := CenterContainer.new()
	centered.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(centered)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 17)
	centered.add_child(stack)
	overlay_title = Label.new()
	overlay_title.text = "W I N D R U N"
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_title.add_theme_font_size_override("font_size", 74)
	overlay_title.add_theme_color_override("font_color", Color("faffed"))
	overlay_title.add_theme_color_override("font_outline_color", Color("2b6350"))
	overlay_title.add_theme_constant_override("outline_size", 5)
	stack.add_child(overlay_title)
	overlay_subtitle = Label.new()
	overlay_subtitle.text = "T H E   A R T   F O U N D A T I O N"
	overlay_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_subtitle.add_theme_font_size_override("font_size", 21)
	overlay_subtitle.add_theme_color_override("font_color", Color("fff2c0"))
	stack.add_child(overlay_subtitle)
	overlay_instructions = Label.new()
	overlay_instructions.text = "PRESS ENTER TO BEGIN\n\nWASD move  •  Mouse look  •  Space jump\nShift sprint  •  Ctrl brake  •  F Zen Mode\nG golden hour  •  M music  •  H hide HUD  •  V grass  •  F3 diagnostics\nEsc pause  •  T restart trial"
	overlay_instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_instructions.add_theme_font_size_override("font_size", 17)
	overlay_instructions.add_theme_color_override("font_color", Color("f9fffb"))
	stack.add_child(overlay_instructions)

func _make_label(parent: Control, xy: Vector2, font_size: int, content: String, color: Color) -> Label:
	var label := Label.new()
	label.position = xy
	label.text = content
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.035, 0.20, 0.14, 0.72))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label

func _show_start_screen() -> void:
	overlay.visible = true
	overlay_title.text = "W I N D R U N"
	overlay_subtitle.text = "T H E   A R T   F O U N D A T I O N"
	opening_art.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _show_status(message: String) -> void:
	mission_label.text = message

func _start_or_resume() -> void:
	started = true
	paused = false
	get_tree().paused = false
	overlay.visible = false
	runner.can_move = true
	get_window().grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _pause_game() -> void:
	paused = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay_title.text = "P A U S E D"
	opening_art.visible = false
	overlay_subtitle.text = "The hills will be here when you return."
	overlay_instructions.text = "PRESS ENTER TO RESUME\n\nEsc also resumes  •  R resets your position\nWASD move  •  Mouse look  •  Space jump\nShift sprint  •  Ctrl brake  •  F Zen Mode"
	overlay.visible = true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		last_key_received = OS.get_keycode_string(event.keycode)
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if not started or paused:
				_start_or_resume()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if started:
				if paused:
					_start_or_resume()
				else:
					_pause_game()
				get_viewport().set_input_as_handled()
		elif started and not paused:
			match event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode:
				KEY_SPACE:
					runner.queue_jump()
				KEY_R:
					runner.reset_runner()
				KEY_T:
					_restart_trial()
				KEY_F:
					zen_mode = not zen_mode
					_show_status("ZEN MODE — JUST RUN" if zen_mode else "BACK TO THE TRIAL")
				KEY_H:
					hud_visible = not hud_visible
					hud_root.visible = hud_visible
				KEY_F3:
					debug_visible = not debug_visible
					input_debug_label.visible = debug_visible
				KEY_V:
					meadow.toggle_grass_density()
				KEY_G:
					meadow.set_golden_hour(not meadow.golden_hour)
				KEY_M:
					music_enabled = not music_enabled
					if music_audio != null:
						if music_enabled:
							music_audio.play()
						else:
							music_audio.stop()
					_show_music_notice()
				KEY_MINUS:
					music_volume_adjust_db = maxf(-14.0, music_volume_adjust_db - 2.0)
					_show_music_notice()
				KEY_EQUAL:
					music_volume_adjust_db = minf(10.0, music_volume_adjust_db + 2.0)
					_show_music_notice()
	if event is InputEventMouseMotion and started and not paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * 0.0024
		camera_pitch = clampf(camera_pitch + event.relative.y * 0.002, 0.08, 0.88)

func _show_music_notice() -> void:
	if music_notice_label == null:
		return
	music_notice_label.text = "MUSIC %s   |   VOLUME OFFSET %s dB   |   - / = to adjust" % ["ON" if music_enabled else "OFF", str(int(music_volume_adjust_db))]
	music_notice_label.visible = true
	music_notice_timer = 3.5

func _restart_trial() -> void:
	# The five checkpoint gates are near spawn, so teleport back to restart.
	runner.reset_runner()
	camera_position_initialized = false
	active_gate = 0
	trial_active = false
	trial_finished = false
	elapsed = 0.0
	_update_gate_appearance()
	_show_status("TRIAL RESET — SEEK THE GOLDEN RING")

func _physics_process(_delta: float) -> void:
	if runner != null:
		runner.movement_yaw = camera_yaw

func _process(delta: float) -> void:
	if runner == null or camera == null:
		return
	meadow.stream_around(runner.global_position, runner.velocity)
	if not paused:
		step_sound_cooldown = maxf(0.0, step_sound_cooldown - delta)
	_update_camera(delta)
	_update_motion_fx(delta)
	if music_notice_timer > 0.0:
		music_notice_timer = maxf(0.0, music_notice_timer - delta)
		if music_notice_timer == 0.0 and music_notice_label != null:
			music_notice_label.visible = false
	if not started or paused:
		return
	if trial_active and not zen_mode:
		elapsed += delta
	_update_exploration(delta)
	var speed_kmh := runner.last_horizontal_speed * 3.6
	if input_debug_label != null:
		input_debug_label.text = "KEY: %s  |  AXIS: %.1f, %.1f  |  GROUND: %s  |  FPS: %d  |  GRASS: %d" % [last_key_received, runner.last_control_axis.x, runner.last_control_axis.y, str(runner.is_on_floor() or runner.terrain_contact), Engine.get_frames_per_second(), meadow.grass_patches.size()]
	speed_label.text = "%03d" % int(round(speed_kmh))
	distance_label.text = "km/h  •  %d m travelled  •  air %.1f s" % [int(runner.distance_travelled), runner.air_time]
	if zen_mode:
		mission_label.text = "ZEN MODE"
		direction_label.text = "No clocks. No objectives. Only the wind."
	elif trial_finished:
		mission_label.text = "COURSE COMPLETE  %.2f s" % elapsed
		direction_label.text = "Personal best: %.2f s   •   T to race again" % best_time
	else:
		mission_label.text = "GATE %d / %d" % [active_gate + 1, gates.size()]
		if trial_active:
			mission_label.text += "    •    %.2f s" % elapsed
		if active_gate < gates.size():
			var goal := gates[active_gate].global_position
			var flat_dist := Vector2(goal.x - runner.global_position.x, goal.z - runner.global_position.z).length()
			direction_label.text = "Golden gate: %d m away   •   Best: %s" % [int(flat_dist), "--" if best_time < 0.0 else "%.2f s" % best_time]
	if music_audio != null and music_enabled:
		music_audio.volume_db = lerpf(-8.0, -12.0, clampf(runner.last_horizontal_speed / 65.0, 0.0, 1.0)) + music_volume_adjust_db
	if wind_audio != null:
		wind_audio.volume_db = lerpf(-35.0, -13.0, clampf(runner.last_horizontal_speed / 65.0, 0.0, 1.0))
		wind_audio.pitch_scale = lerpf(0.85, 1.28, clampf(runner.last_horizontal_speed / 70.0, 0.0, 1.0))

func _update_camera(delta: float) -> void:
	var speed := runner.last_horizontal_speed
	var speed_fraction := clampf(speed / 60.0, 0.0, 1.0)
	# Stay close enough to read the character's run cycle at high speed.
	var camera_distance := lerpf(6.3, 8.4, speed_fraction)
	if not (runner.is_on_floor() or runner.terrain_contact):
		camera_distance += 1.1
	var camera_height := lerpf(2.4, 3.2, speed_fraction)
	camera_launch_kick = move_toward(camera_launch_kick, 0.0, delta * 0.65)
	camera_land_kick = move_toward(camera_land_kick, 0.0, delta * 1.2)
	var orbit := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch))
	var focus := runner.global_position + Vector3(0.0, 1.35 + speed_fraction * 0.45, 0.0)
	var desired := focus + orbit * camera_distance + Vector3(0.0, camera_height * 0.3 + camera_launch_kick * 0.35 - camera_land_kick * 0.32, 0.0)
	# Terrain-aware camera clearance (also safe outside a physics tick).
	desired.y = maxf(desired.y, meadow.height_at(desired.x, desired.z) + 2.4)
	if not camera_position_initialized:
		camera.global_position = desired
		camera_position_initialized = true
	else:
		camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-delta * 5.8))
	camera.look_at(focus, Vector3.UP)
	# A restrained camera bank follows steering at speed, without screen shake.
	var target_bank := runner.last_control_axis.x * speed_fraction * 0.027
	camera_bank = lerpf(camera_bank, target_bank, 1.0 - exp(-delta * 4.0))
	camera.rotate_object_local(Vector3.FORWARD, camera_bank)
	camera.fov = lerpf(camera.fov, lerpf(67.0, 76.0, speed_fraction) + camera_launch_kick * 0.8, 1.0 - exp(-delta * 3.5))

func _setup_sounds() -> void:
	# All sounds in assets/ are original procedural sound effects, no music assets.
	# Three low-passed grass swishes: subtle variation prevents 'tak-tak-tak'.
	for path in ["res://assets/step_grass.wav", "res://assets/step_grass_b.wav", "res://assets/step_grass_c.wav"]:
		var player := _create_sound_player(path, -28.0)
		if player != null:
			step_audios.append(player)
	jump_audio = _create_sound_player("res://assets/takeoff.wav", -12.0)
	land_audio = _create_sound_player("res://assets/landing.wav", -14.0)
	nature_audio = _create_sound_player("res://assets/meadow_birds.wav", -24.0)
	if nature_audio != null:
		if nature_audio.stream is AudioStreamWAV:
			(nature_audio.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		nature_audio.play()

func _create_sound_player(path: String, volume: float) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = volume
	add_child(player)
	return player

func _on_runner_jump(takeoff_speed: float) -> void:
	camera_launch_kick = clampf(takeoff_speed / 55.0, 0.35, 0.95)
	if jump_audio != null:
		jump_audio.pitch_scale = lerpf(0.92, 1.20, clampf(takeoff_speed / 65.0, 0.0, 1.0))
		jump_audio.play()

func _on_runner_land(impact_strength: float) -> void:
	camera_land_kick = maxf(camera_land_kick, impact_strength)
	if land_audio != null:
		land_audio.volume_db = lerpf(-24.0, -10.0, impact_strength)
		land_audio.pitch_scale = lerpf(1.08, 0.84, impact_strength)
		land_audio.play()
	if landing_dust != null:
		landing_dust.global_position = runner.global_position + Vector3.UP * 0.12
		landing_dust.restart()
		landing_dust.emitting = true

func _on_runner_step(step_speed: float) -> void:
	if paused or not started or step_audios.is_empty() or step_sound_cooldown > 0.0:
		return
	var speed_factor := clampf(step_speed / 60.0, 0.0, 1.0)
	# The visual leg animation can cycle extremely fast; audio should not.
	step_sound_cooldown = lerpf(0.45, 0.31, speed_factor) * footstep_rng.randf_range(0.93, 1.11)
	# Alternate between 3 softer samples; never repeat the same one twice.
	var voice_offset := 1
	if step_audios.size() > 1:
		voice_offset = footstep_rng.randi_range(1, step_audios.size() - 1)
	last_footstep_index = (last_footstep_index + voice_offset) % step_audios.size()
	var voice := step_audios[last_footstep_index]
	voice.pitch_scale = footstep_rng.randf_range(0.90, 1.05)
	voice.volume_db = lerpf(-29.0, -25.0, speed_factor) + footstep_rng.randf_range(-2.0, 0.0)
	voice.play()

func _build_motion_fx() -> void:
	# CPU particles are supported by the Compatibility renderer on integrated GPUs.
	var sprite := SphereMesh.new()
	sprite.radius = 0.095
	sprite.height = 0.19
	sprite.radial_segments = 5
	sprite.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.95, 0.65, 0.44)
	sprite.material = mat
	running_dust = CPUParticles3D.new()
	running_dust.name = "Grass_and_dust_trail"
	running_dust.mesh = sprite
	running_dust.amount = 30
	running_dust.lifetime = 0.55
	running_dust.local_coords = false
	running_dust.direction = Vector3(0.0, 0.8, 0.0)
	running_dust.spread = 75.0
	running_dust.gravity = Vector3(0.0, -1.4, 0.0)
	running_dust.initial_velocity_min = 0.6
	running_dust.initial_velocity_max = 2.0
	running_dust.scale_amount_min = 0.40
	running_dust.scale_amount_max = 0.95
	running_dust.emitting = false
	add_child(running_dust)
	landing_dust = CPUParticles3D.new()
	landing_dust.name = "Soft_landing_puff"
	landing_dust.mesh = sprite
	landing_dust.amount = 18
	landing_dust.lifetime = 0.38
	landing_dust.one_shot = true
	landing_dust.explosiveness = 1.0
	landing_dust.local_coords = false
	landing_dust.direction = Vector3.UP
	landing_dust.spread = 90.0
	landing_dust.initial_velocity_min = 1.5
	landing_dust.initial_velocity_max = 3.4
	landing_dust.gravity = Vector3(0.0, -5.0, 0.0)
	landing_dust.scale_amount_min = 0.55
	landing_dust.scale_amount_max = 1.7
	landing_dust.emitting = false
	add_child(landing_dust)

func _update_motion_fx(_delta: float) -> void:
	if running_dust == null or runner == null:
		return
	var grounded := runner.is_on_floor() or runner.terrain_contact
	var speed := runner.last_horizontal_speed
	running_dust.emitting = started and not paused and grounded and speed > 17.0
	if running_dust.emitting:
		var travel := Vector3(runner.velocity.x, 0.0, runner.velocity.z).normalized()
		running_dust.global_position = runner.global_position - travel * 0.45 + Vector3.UP * 0.14

func _load_records() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(json) == TYPE_DICTIONARY and json.has("best_time"):
		best_time = float(json["best_time"])

func _save_records() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"best_time": best_time, "total_distance": runner.distance_travelled}))


func _update_exploration(delta: float) -> void:
	if landmarks == null:
		return
	var found := landmarks.update_player(runner.global_position)
	if found != "":
		_save_discoveries()
		discovery_flash_timer = 4.0
		discovery_flash.text = "DISCOVERED!\n" + found
		discovery_flash.visible = true
		if discovery_audio != null:
			discovery_audio.play()
	if discovery_flash_timer > 0.0:
		discovery_flash_timer = maxf(0.0, discovery_flash_timer - delta)
		discovery_flash.modulate.a = minf(1.0, discovery_flash_timer * 0.7)
		if discovery_flash_timer <= 0.0:
			discovery_flash.visible = false
	var complete := landmarks.count_visited()
	var total := landmarks.count_total()
	var nearest := landmarks.get_nearest_unvisited(runner.global_position)
	if nearest.is_empty():
		discoveries_label.text = "DISCOVERIES %d/%d   •   ALL SCENIC PLACES FOUND" % [complete, total]
		return
	var point: Vector2 = nearest["position"]
	var dx := point.x - runner.global_position.x
	var dz := point.y - runner.global_position.z
	var bearing := atan2(dx, -dz)
	var relative := wrapf(bearing + camera_yaw, -PI, PI)
	var arrows := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
	var octant := posmod(int(round(relative / (PI / 4.0))), 8)
	discoveries_label.text = "SCENIC %d/%d   %s  %s  %dm" % [complete, total, arrows[octant], str(nearest["name"]), int(nearest["distance"])]

func _load_discoveries() -> void:
	var path := "user://windrun_landmarks.json"
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) == TYPE_DICTIONARY and data.has("visited") and typeof(data["visited"]) == TYPE_ARRAY:
		landmarks.restore_visited(data["visited"])

func _save_discoveries() -> void:
	var file := FileAccess.open("user://windrun_landmarks.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"visited": landmarks.get_visited_ids()}))
