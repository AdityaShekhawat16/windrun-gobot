extends CharacterBody3D
class_name WindRunner

signal jumped(takeoff_speed: float)
signal landed(impact_strength: float)
signal stepped(step_speed: float)
## Fast, controllable velocity-based locomotion. Values are in metres/seconds.

const WALK_ACCEL := 23.0
const RUN_ACCEL := 31.0
const SPRINT_ACCEL := 38.0
const AIR_ACCEL := 6.0
const GROUND_TURN_RATE_SLOW := 5.4  # rad/s; grounded steering at walking speed
const GROUND_TURN_RATE_FAST := 3.2  # rad/s; still controllable at 160+ km/h
const DOWNHILL_GRAVITY := 29.0
const GROUND_DECEL := 2.2
const BRAKE_DECEL := 30.0
const AIR_DRAG := 0.18
const SPEED_SOFT_CAP := 52.0
const SPEED_ABSOLUTE_CAP := 86.0
const JUMP_SPEED := 18.0
const GRAVITY := 24.0
const JUMP_BUFFER := 0.16
const COYOTE_TIME := 0.13

var movement_yaw := 0.0
var can_move := true
var world: MeadowWorld
var remaining_jump_buffer := 0.0
var remaining_coyote := 0.0
var visual_root: Node3D
var head: MeshInstance3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var scarf_ribbon: MeshInstance3D
var scarf_fabric: Material
var left_coat_tail: Node3D
var right_coat_tail: Node3D
var left_elbow: Node3D
var right_elbow: Node3D
var left_knee: Node3D
var right_knee: Node3D
var upper_body: Node3D
var hair_tuft: Node3D
var scarf_phase := 0.0
var animation_state := "idle"
var landing_recovery := 0.0
var was_grounded := false
var landing_strength := 0.0
var run_cycle := 0.0
var mesh_forward_yaw := 0.0
var last_horizontal_speed := 0.0
var air_time := 0.0
var best_air_time := 0.0
var distance_travelled := 0.0
var last_control_axis := Vector2.ZERO
var terrain_contact := false

# Godot actions are preferred, with raw-key fallback for diagnosing keyboard layouts.
func _key_down(key: Key) -> bool:
	return Input.is_physical_key_pressed(key) or Input.is_key_pressed(key)

func _movement_axis() -> Vector2:
	var action_axis := Input.get_vector("wind_left", "wind_right", "wind_forward", "wind_backward")
	if action_axis.length_squared() > 0.0:
		return action_axis
	var fallback := Vector2.ZERO
	if _key_down(KEY_W) or _key_down(KEY_UP):
		fallback.y -= 1.0
	if _key_down(KEY_S) or _key_down(KEY_DOWN):
		fallback.y += 1.0
	if _key_down(KEY_A) or _key_down(KEY_LEFT):
		fallback.x -= 1.0
	if _key_down(KEY_D) or _key_down(KEY_RIGHT):
		fallback.x += 1.0
	return fallback.normalized()

func _ready() -> void:
	name = "The_Runner"
	floor_snap_length = 1.25
	floor_stop_on_slope = false
	floor_constant_speed = false
	floor_max_angle = deg_to_rad(63.0)
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.9
	collider.shape = capsule
	collider.position.y = 1.0
	add_child(collider)
	_make_avatar()

func _make_avatar() -> void:
	# v0.9: true hierarchical procedural puppet with shoulder/elbow and hip/knee pivots.
	# Each articulated joint is animated separately; no downloaded meshes or plugins.
	visual_root = Node3D.new()
	visual_root.name = "Windrunner_articulated"
	add_child(visual_root)
	var jacket := _material("eee6cb")
	var jacket_shadow := _material("d5d6bf")
	var trim := _material("426f69")
	var pants := _material("354a5a")
	var skin := _material("c99470")
	var hair_mat := _material("25414a")
	var scarf_mat := _material("f3bb53")
	var scarf_tip := _material("ffe3a2")
	var boots := _material("243439")

	upper_body = Node3D.new()
	upper_body.name = "Torso_spine"
	visual_root.add_child(upper_body)
	var torso := _capsule_part("Canvas_travel_coat", Vector3(0, 1.38, 0), 0.34, 0.90, jacket)
	torso.scale = Vector3(1.08, 1.0, 0.78)
	upper_body.add_child(torso)
	upper_body.add_child(_box_part("Coat_hem", Vector3(0, 1.00, 0.07), Vector3(0.69, 0.20, 0.40), jacket_shadow))
	upper_body.add_child(_box_part("Belt", Vector3(0, 0.97, 0), Vector3(0.65, 0.10, 0.37), trim))
	# Quiet seam and collar details that read at third-person camera distance.
	upper_body.add_child(_capsule_part("Cloth_collar", Vector3(0, 1.80, -0.07), 0.255, 0.18, jacket_shadow))
	upper_body.add_child(_box_part("Travel_coat_seam", Vector3(0, 1.37, -0.277), Vector3(0.027, 0.51, 0.026), jacket_shadow))

	head = _sphere_part("Head", Vector3(0, 2.05, -0.035), Vector3(0.31, 0.36, 0.29), skin)
	upper_body.add_child(head)
	upper_body.add_child(_sphere_part("Hair_cap", Vector3(0, 2.29, 0.02), Vector3(0.34, 0.17, 0.32), hair_mat))
	hair_tuft = Node3D.new()
	hair_tuft.name = "Wind_swept_hair"
	hair_tuft.position = Vector3(0, 2.35, 0.08)
	hair_tuft.add_child(_capsule_part("Back_hair", Vector3(0, -0.03, 0.20), 0.105, 0.48, hair_mat))
	upper_body.add_child(hair_tuft)

	# Shoulder -> elbow -> hand chains. Arm and forearm have distinct poses.
	left_arm = Node3D.new()
	left_arm.name = "Left_shoulder"
	left_arm.position = Vector3(-0.42, 1.72, 0)
	left_arm.add_child(_capsule_part("Upper_left_sleeve", Vector3(-0.015, -0.24, 0), 0.145, 0.52, jacket))
	left_elbow = Node3D.new()
	left_elbow.name = "Left_elbow"
	left_elbow.position = Vector3(-0.015, -0.48, 0)
	left_elbow.add_child(_capsule_part("Left_forearm", Vector3(0, -0.20, 0), 0.105, 0.43, jacket_shadow))
	left_elbow.add_child(_sphere_part("Left_hand", Vector3(0, -0.43, 0), Vector3(0.12, 0.13, 0.12), skin))
	left_arm.add_child(left_elbow)
	upper_body.add_child(left_arm)

	right_arm = Node3D.new()
	right_arm.name = "Right_shoulder"
	right_arm.position = Vector3(0.42, 1.72, 0)
	right_arm.add_child(_capsule_part("Upper_right_sleeve", Vector3(0.015, -0.24, 0), 0.145, 0.52, jacket))
	right_elbow = Node3D.new()
	right_elbow.name = "Right_elbow"
	right_elbow.position = Vector3(0.015, -0.48, 0)
	right_elbow.add_child(_capsule_part("Right_forearm", Vector3(0, -0.20, 0), 0.105, 0.43, jacket_shadow))
	right_elbow.add_child(_sphere_part("Right_hand", Vector3(0, -0.43, 0), Vector3(0.12, 0.13, 0.12), skin))
	right_arm.add_child(right_elbow)
	upper_body.add_child(right_arm)

	# Hip -> knee -> foot chains: independent leg lift, knee flex and ankle lean.
	left_leg = Node3D.new()
	left_leg.name = "Left_hip"
	left_leg.position = Vector3(-0.19, 0.94, 0)
	left_leg.add_child(_capsule_part("Left_thigh", Vector3(0, -0.24, 0), 0.16, 0.54, pants))
	left_knee = Node3D.new()
	left_knee.name = "Left_knee"
	left_knee.position = Vector3(0, -0.48, 0)
	left_knee.add_child(_capsule_part("Left_shin", Vector3(0, -0.22, 0), 0.12, 0.48, pants))
	left_knee.add_child(_box_part("Left_shoe", Vector3(0, -0.44, -0.12), Vector3(0.28, 0.17, 0.48), boots))
	left_leg.add_child(left_knee)
	visual_root.add_child(left_leg)

	right_leg = Node3D.new()
	right_leg.name = "Right_hip"
	right_leg.position = Vector3(0.19, 0.94, 0)
	right_leg.add_child(_capsule_part("Right_thigh", Vector3(0, -0.24, 0), 0.16, 0.54, pants))
	right_knee = Node3D.new()
	right_knee.name = "Right_knee"
	right_knee.position = Vector3(0, -0.48, 0)
	right_knee.add_child(_capsule_part("Right_shin", Vector3(0, -0.22, 0), 0.12, 0.48, pants))
	right_knee.add_child(_box_part("Right_shoe", Vector3(0, -0.44, -0.12), Vector3(0.28, 0.17, 0.48), boots))
	right_leg.add_child(right_knee)
	visual_root.add_child(right_leg)

	upper_body.add_child(_capsule_part("Golden_scarf_collar", Vector3(0, 1.80, 0), 0.255, 0.53, scarf_mat))
	scarf_fabric = scarf_mat
	(scarf_fabric as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	scarf_ribbon = MeshInstance3D.new()
	scarf_ribbon.name = "Continuous_flowing_scarf"
	scarf_ribbon.material_override = scarf_fabric
	scarf_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	upper_body.add_child(scarf_ribbon)
	# Tail of the travelling coat, pinned to the hips and loosely trailing.
	left_coat_tail = Node3D.new()
	left_coat_tail.position = Vector3(-0.19, 1.0, 0.20)
	left_coat_tail.add_child(_capsule_part("Left_coat_flap", Vector3(0, -0.20, 0.06), 0.12, 0.49, jacket))
	upper_body.add_child(left_coat_tail)
	right_coat_tail = Node3D.new()
	right_coat_tail.position = Vector3(0.19, 1.0, 0.20)
	right_coat_tail.add_child(_capsule_part("Right_coat_flap", Vector3(0, -0.20, 0.06), 0.12, 0.49, jacket))
	upper_body.add_child(right_coat_tail)
	_update_scarf_ribbon(0.0, 0.0)

func _material(hex_code: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex_code)
	m.roughness = 0.95
	return m

func _box_part(part_name: String, pos: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = material
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = pos
	return part

func _capsule_part(part_name: String, pos: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 3
	mesh.material = material
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = pos
	return part

func _sphere_part(part_name: String, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = pos
	part.scale = size
	return part

func queue_jump() -> void:
	remaining_jump_buffer = JUMP_BUFFER

func _physics_process(delta: float) -> void:
	if not can_move:
		return
	# Some graphics-driver / trimesh combinations may visually show the ground
	# without reporting an is_on_floor() contact. Use the known terrain height as
	# a physics fallback so the avatar cannot stay suspended under the world.
	var ground_y := world.height_at(global_position.x, global_position.z) if world != null else -100000.0
	terrain_contact = world != null and global_position.y <= ground_y + 0.42 and velocity.y <= 1.0
	var on_ground := is_on_floor() or terrain_contact
	remaining_jump_buffer = maxf(0.0, remaining_jump_buffer - delta)
	if on_ground:
		remaining_coyote = COYOTE_TIME
		air_time = 0.0
	else:
		remaining_coyote = maxf(0.0, remaining_coyote - delta)
		air_time += delta
		best_air_time = maxf(air_time, best_air_time)

	var axis := _movement_axis()
	last_control_axis = axis
	var camera_forward := Vector3(-sin(movement_yaw), 0.0, -cos(movement_yaw))
	var camera_right := Vector3(cos(movement_yaw), 0.0, -sin(movement_yaw))
	var input_direction := (camera_forward * -axis.y + camera_right * axis.x).normalized()
	var wants_sprint := Input.is_action_pressed("wind_sprint") or _key_down(KEY_SHIFT)
	var wants_brake := Input.is_action_pressed("wind_brake") or _key_down(KEY_CTRL)
	var accel := RUN_ACCEL if not wants_sprint else SPRINT_ACCEL
	var horizontal := Vector3(velocity.x, 0, velocity.z)

	if on_ground:
		# Gravity component parallel to ground: downhills genuinely contribute speed.
		var normal := get_floor_normal() if is_on_floor() else world.surface_normal_at(global_position.x, global_position.z)
		var downhill := Vector3.DOWN.slide(normal)
		horizontal += Vector3(downhill.x, 0.0, downhill.z) * DOWNHILL_GRAVITY * delta
		if axis.length_squared() > 0.0:
			# Steering must redirect the EXISTING velocity, not just add a tiny
			# perpendicular force. Otherwise a 45 m/s sprint appears W-only.
			# The rate is limited, so direction changes are smooth and speed remains
			# momentum-driven instead of teleporting the character sideways.
			var speed_before := horizontal.length()
			if speed_before > 0.3:
				var velocity_2d := Vector2(horizontal.x, horizontal.z)
				var desired_2d := Vector2(input_direction.x, input_direction.z)
				var turn_limit := lerpf(GROUND_TURN_RATE_SLOW, GROUND_TURN_RATE_FAST, clampf(speed_before / 52.0, 0.0, 1.0)) * delta
				var angle_difference := velocity_2d.angle_to(desired_2d)
				var turned := velocity_2d.rotated(clampf(angle_difference, -turn_limit, turn_limit))
				horizontal.x = turned.x
				horizontal.z = turned.y
			var control := accel
			if horizontal.length() > SPEED_SOFT_CAP:
				control *= 0.2
			horizontal += input_direction * control * delta
		else:
			horizontal = horizontal.move_toward(Vector3.ZERO, GROUND_DECEL * delta)
		if wants_brake:
			horizontal = horizontal.move_toward(Vector3.ZERO, BRAKE_DECEL * delta)
		# Horizontal momentum is the source of jump distance. Non-jump frames
		# press gently into the floor so the character stays attached to hills.
		# Previously, the tangent's upward velocity could disable floor snapping
		# and repeatedly send the character into a false airborne state.
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		if remaining_jump_buffer > 0.0 and remaining_coyote > 0.0:
			var terrain_up_speed := maxf(0.0, horizontal.slide(normal).y)
			velocity.y = JUMP_SPEED + minf(terrain_up_speed * 0.32, 4.0)
			remaining_jump_buffer = 0.0
			remaining_coyote = 0.0
			floor_snap_length = 0.0
			jumped.emit(horizontal.length())
		else:
			velocity.y = -2.0
			floor_snap_length = 1.25
	else:
		# Air steering is intentionally modest. Launch momentum dominates the flight.
		horizontal += input_direction * AIR_ACCEL * delta
		horizontal = horizontal.move_toward(Vector3.ZERO, AIR_DRAG * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		velocity.y -= GRAVITY * delta
		floor_snap_length = 0.0
		if remaining_jump_buffer > 0.0 and remaining_coyote > 0.0:
			velocity.y = maxf(velocity.y, 0.0) + JUMP_SPEED
			remaining_jump_buffer = 0.0
			remaining_coyote = 0.0
			jumped.emit(horizontal.length())
	if Vector2(velocity.x, velocity.z).length() > SPEED_ABSOLUTE_CAP:
		var limited := Vector2(velocity.x, velocity.z).normalized() * SPEED_ABSOLUTE_CAP
		velocity.x = limited.x
		velocity.z = limited.y

	var impact_velocity := absf(velocity.y)
	move_and_slide()
	# Keep the visible surface and player feet in agreement. This also
	# covers high-speed frames where the solver might briefly miss the mesh.
	if world != null:
		var terrain_y := world.height_at(global_position.x, global_position.z)
		if global_position.y < terrain_y + 0.12 and velocity.y <= 0.0:
			global_position.y = terrain_y + 0.12
			velocity.y = 0.0
		terrain_contact = is_on_floor() or (global_position.y <= terrain_y + 0.38 and velocity.y <= 1.0)
	if not on_ground and terrain_contact and air_time > 0.16:
		landed.emit(clampf(impact_velocity / 37.0, 0.15, 1.0))
	last_horizontal_speed = Vector2(velocity.x, velocity.z).length()
	distance_travelled += last_horizontal_speed * delta
	_animate_runner(delta, input_direction, on_ground or terrain_contact)
	# No horizontal world boundary: new terrain chunks stream ahead of us.
	if global_position.y < -250.0:
		reset_runner()

func _animate_runner(delta: float, input_dir: Vector3, on_ground: bool) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	var facing := horizontal if speed > 1.5 else input_dir
	if facing.length_squared() > 0.05:
		var target_yaw := atan2(-facing.x, -facing.z)
		mesh_forward_yaw = lerp_angle(mesh_forward_yaw, target_yaw, clampf(delta * 8.0, 0.0, 1.0))
	visual_root.rotation.y = mesh_forward_yaw
	var speed_fraction := clampf(speed / 56.0, 0.0, 1.0)
	var is_running := speed > 3.0
	if on_ground:
		if not was_grounded:
			landing_recovery = 0.22
		if landing_recovery > 0.0:
			animation_state = "land"
		elif speed < 0.5:
			animation_state = "idle"
		elif speed < 9.0:
			animation_state = "walk"
		elif speed < 27.0:
			animation_state = "run"
		else:
			animation_state = "sprint"
		var previous_step_index := int(floor(run_cycle / PI))
		run_cycle += delta * (2.2 + minf(speed, 54.0) * 0.18)
		if is_running and int(floor(run_cycle / PI)) != previous_step_index:
			stepped.emit(speed)
	else:
		animation_state = "takeoff" if velocity.y > 5.0 else ("glide" if velocity.y > -4.0 else "fall")
		landing_recovery = 0.0
	landing_recovery = maxf(0.0, landing_recovery - delta)
	was_grounded = on_ground

	# Articulated posing. Every bone pivot has its own target; damping produces
	# smooth blending across idle / walk / sprint / leap / fall / land.
	var phase := sin(run_cycle)
	var arm_target := 0.0
	var leg_target := 0.0
	var elbow_target := -0.18
	var knee_base := 0.09
	var forward_lean := -0.04
	var bob := 0.0
	if animation_state == "walk":
		arm_target = phase * 0.32
		leg_target = phase * 0.38
		elbow_target = -0.27
		knee_base = 0.14
		bob = absf(phase) * 0.025
	elif animation_state == "run" or animation_state == "sprint":
		var stride := 0.64 if animation_state == "run" else 1.02
		arm_target = phase * stride * 0.82
		leg_target = phase * stride
		elbow_target = -0.57 if animation_state == "run" else -0.91
		knee_base = 0.20 if animation_state == "run" else 0.33
		forward_lean = -0.20 if animation_state == "run" else -0.37
		bob = absf(phase) * (0.035 if animation_state == "run" else 0.055)
	elif animation_state == "takeoff":
		arm_target = -0.90
		leg_target = 0.38
		elbow_target = -0.35
		knee_base = 0.45
		forward_lean = -0.14
	elif animation_state == "glide":
		arm_target = -0.42
		leg_target = 0.12
		elbow_target = -0.18
		knee_base = 0.23
		forward_lean = 0.03
	elif animation_state == "fall":
		arm_target = 0.30
		leg_target = -0.10
		elbow_target = -0.66
		knee_base = 0.51
		forward_lean = 0.15
	elif animation_state == "land":
		arm_target = -0.16
		leg_target = 0.16
		elbow_target = -0.73
		knee_base = 0.75
		forward_lean = -0.28
		bob = -0.09 * (landing_recovery / 0.22)
	else:
		# Tiny breathing motion when stationary.
		bob = sin(float(Time.get_ticks_msec()) * 0.0013) * 0.012

	var blend := 1.0 - exp(-delta * 11.0)
	left_arm.rotation.x = lerpf(left_arm.rotation.x, -arm_target, blend)
	right_arm.rotation.x = lerpf(right_arm.rotation.x, arm_target, blend)
	left_leg.rotation.x = lerpf(left_leg.rotation.x, leg_target, blend)
	right_leg.rotation.x = lerpf(right_leg.rotation.x, -leg_target, blend)
	left_elbow.rotation.x = lerpf(left_elbow.rotation.x, elbow_target + absf(phase) * speed_fraction * 0.12, blend)
	right_elbow.rotation.x = lerpf(right_elbow.rotation.x, elbow_target + absf(phase) * speed_fraction * 0.12, blend)
	left_knee.rotation.x = lerpf(left_knee.rotation.x, knee_base + maxf(0.0, -phase) * speed_fraction * 0.65, blend)
	right_knee.rotation.x = lerpf(right_knee.rotation.x, knee_base + maxf(0.0, phase) * speed_fraction * 0.65, blend)
	# Counter-rotate the torso when turning; give shoulders some life.
	var side_axis := last_control_axis.x
	upper_body.rotation.z = lerpf(upper_body.rotation.z, -side_axis * 0.10 * speed_fraction, blend)
	upper_body.rotation.y = lerpf(upper_body.rotation.y, phase * 0.055 * speed_fraction + side_axis * 0.045 * speed_fraction, blend)
	visual_root.rotation.x = lerpf(visual_root.rotation.x, forward_lean, 1.0 - exp(-delta * 7.0))
	visual_root.position.y = lerpf(visual_root.position.y, bob, blend)
	hair_tuft.rotation.x = lerpf(hair_tuft.rotation.x, speed_fraction * 0.48 + sin(run_cycle * 0.5) * 0.05, blend)

	# Smooth, connected ribbon follows the runner's speed and the air currents.
	# Its 12 short cloth spans are CPU-cheap and do not affect locomotion.
	scarf_phase += delta * (0.9 + speed_fraction * 3.1)
	_update_scarf_ribbon(speed_fraction, velocity.y)
	if left_coat_tail != null:
		left_coat_tail.rotation.x = lerpf(left_coat_tail.rotation.x, -0.09 - speed_fraction * 0.32 + sin(run_cycle + 0.65) * 0.055, blend)
		right_coat_tail.rotation.x = lerpf(right_coat_tail.rotation.x, -0.09 - speed_fraction * 0.32 + sin(run_cycle + 2.9) * 0.055, blend)
		left_coat_tail.rotation.z = lerpf(left_coat_tail.rotation.z, -0.025 + side_axis * 0.05, blend)
		right_coat_tail.rotation.z = lerpf(right_coat_tail.rotation.z, 0.025 + side_axis * 0.05, blend)

func _update_scarf_ribbon(speed_fraction: float, vertical_speed: float) -> void:
	if scarf_ribbon == null:
		return
	# A continuous double-sided surface, with a narrow taper near the tip.
	# No expensive skeletal/cloth simulation, just smooth delayed wave motion.
	var segments := 12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left_edge: Array[Vector3] = []
	var right_edge: Array[Vector3] = []
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var delayed := scarf_phase - t * 2.6
		var sway := sin(delayed) * (0.025 + speed_fraction * 0.15) * t
		var rise := speed_fraction * 0.20 * t + sin(delayed * 0.8) * 0.052 * t
		var vertical_drag := clampf(vertical_speed / 48.0, -0.22, 0.22) * t
		var center := Vector3(0.10 + sway, 1.79 + rise - vertical_drag - 0.07 * t, 0.22 + 2.65 * t)
		var width := lerpf(0.27, 0.08, t) * (1.0 + sin(delayed * 0.4) * 0.04)
		left_edge.append(center + Vector3(-width * 0.5, 0.0, 0.0))
		right_edge.append(center + Vector3(width * 0.5, 0.0, 0.0))
	for i in range(segments):
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.0, float(i) / segments))
		st.add_vertex(left_edge[i])
		st.set_uv(Vector2(1.0, float(i) / segments))
		st.add_vertex(right_edge[i])
		st.set_uv(Vector2(0.0, float(i + 1) / segments))
		st.add_vertex(left_edge[i + 1])
		st.set_uv(Vector2(1.0, float(i) / segments))
		st.add_vertex(right_edge[i])
		st.set_uv(Vector2(1.0, float(i + 1) / segments))
		st.add_vertex(right_edge[i + 1])
		st.set_uv(Vector2(0.0, float(i + 1) / segments))
		st.add_vertex(left_edge[i + 1])
	scarf_ribbon.mesh = st.commit()

func reset_runner() -> void:
	var spawn_y := 10.0
	if world != null:
		spawn_y = world.height_at(0.0, 0.0) + 0.25
	global_position = Vector3(0, spawn_y, 0)
	terrain_contact = false
	last_control_axis = Vector2.ZERO
	velocity = Vector3.ZERO
	last_horizontal_speed = 0.0
	air_time = 0.0
	remaining_jump_buffer = 0.0
