extends Node3D
class_name MeadowWorld
## Streaming, deterministic terrain. Every tile is generated from WORLD coordinates,
## so its edges match its neighbours and the landscape has no fixed border.
## Detailed nearby tiles contain collision, trees and grass; distant tiles are
## cheaper visual-only hills. Unused tiles are discarded to bound memory use.

const CHUNK_SIZE := 224.0
const DETAIL_RADIUS := 2       # 5 x 5: terrain, collision, grass and trees
const HORIZON_RADIUS := 3      # 7 x 7: distant rolling terrain
const NEAR_SUBDIVISIONS := 40
const FAR_SUBDIVISIONS := 24
const GRASS_PER_TILE := 890
const TREES_PER_TILE := 5
const FLOWERS_PER_TILE := 280
const STONES_PER_TILE := 14
const SHRUBS_PER_TILE := 23
# v0.7: world-anchored, streamed grass across a broad field of view.
# The old 62*1.6 m carpet covered only ~99 m and visibly chased the player.
const GRASS_PATCH_SIZE := 64.0
const GRASS_PATCH_RADIUS := 5         # 11x11 patches: ~704 m-wide coverage
const GRASS_PATCHES_PER_FRAME := 3     # Incremental population; no massive spikes
const GRASS_PATCH_INSTANCES := 510    # ~62k card tufts before GPU culling
const GRASS_LOOKAHEAD_SECONDS := 1.50
const GRASS_MAX_LOOKAHEAD := 112.0
const CHUNKS_PER_FRAME := 1

var terrain_noise := FastNoiseLite.new()
var chunks: Dictionary = {}              # Vector2i -> {node: Node3D, detail: bool}
var pending_chunks: Array[Vector2i] = []
var player_tile := Vector2i.ZERO
var stream_target := Vector3.ZERO

var terrain_material: ShaderMaterial
var grass_mesh: ArrayMesh
var flower_mesh: ArrayMesh
var trunk_mesh: CylinderMesh
var foliage_mesh: SphereMesh
var foliage_material: StandardMaterial3D
var branch_mesh: CylinderMesh
var stone_mesh: SphereMesh
var shrub_mesh: SphereMesh
var clouds_root: Node3D
var dense_grass_enabled := true
var grass_patches_root: Node3D
var grass_patches: Dictionary = {} # Vector2i -> MultiMeshInstance3D
var pending_grass_patches: Array[Vector2i] = []
var grass_patch_center := Vector2i(9999999, 9999999)
var sun_light: DirectionalLight3D
var meadow_sky: PanoramaSkyMaterial
var daylight_sky: Texture2D
var sunset_sky: Texture2D
var meadow_env: Environment
var golden_hour := false
var cloud_time := 0.0

func _ready() -> void:
	terrain_noise.seed = 48321
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.frequency = 0.007
	_create_shared_meshes_and_materials()
	_build_near_grass()
	# Painterly equirectangular panoramas plus atmospheric sprite cloud banks.
	_build_lighting()
	_build_clouds()
	# Build the immediate ground synchronously, before the runner is spawned.
	# The remaining horizon streams in over subsequent frames.
	for z in range(-1, 2):
		for x in range(-1, 2):
			_build_chunk(Vector2i(x, z), true)
	_schedule_missing_tiles()

func height_at(x: float, z: float) -> float:
	# Pure function of absolute world position: smooth across tile boundaries.
	var broad := 13.5 * sin(x / 58.0) + 11.0 * cos(z / 67.0)
	var rolling := 9.0 * sin((x + z * 0.57) / 78.0)
	var rhythm := 4.8 * cos((x - z) / 44.0)
	var natural := terrain_noise.get_noise_2d(x, z) * 3.1
	return broad + rolling + rhythm + natural

func surface_normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	var slope_x := (height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e)
	var slope_z := (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e)
	return Vector3(-slope_x, 1.0, -slope_z).normalized()

func stream_around(position: Vector3, movement_velocity: Vector3 = Vector3.ZERO) -> void:
	stream_target = position
	_update_near_grass(position, movement_velocity)
	var next_tile := Vector2i(floori((position.x + CHUNK_SIZE * 0.5) / CHUNK_SIZE), floori((position.z + CHUNK_SIZE * 0.5) / CHUNK_SIZE))
	if next_tile != player_tile:
		player_tile = next_tile
		# A reset can teleport thousands of metres. Give the runner physical
		# ground immediately rather than waiting for the next stream tick.
		if not chunks.has(next_tile):
			_build_chunk(next_tile, true)
		else:
			var current_entry: Dictionary = chunks[next_tile]
			if not bool(current_entry["detail"]):
				_build_chunk(next_tile, true)
		_schedule_missing_tiles()
	if clouds_root != null:
		# Decorative clouds remain around the camera even far from spawn.
		clouds_root.position = Vector3(position.x + sin(cloud_time * 0.045) * 12.0, 0.0, position.z + sin(cloud_time * 0.027) * 17.0)

func _process(delta: float) -> void:
	cloud_time += delta
	for _i in range(CHUNKS_PER_FRAME):
		if pending_chunks.is_empty():
			break
		var target: Vector2i = pending_chunks.pop_front()
		var ring := maxi(absi(target.x - player_tile.x), absi(target.y - player_tile.y))
		if ring > HORIZON_RADIUS:
			continue
		var detail_needed := ring <= DETAIL_RADIUS
		if chunks.has(target):
			var old_entry: Dictionary = chunks[target]
			# Detailed tiles are allowed to stay detailed until they are evicted;
			# avoiding downgrade/re-upgrade prevents unnecessary collision churn.
			if bool(old_entry["detail"]) or not detail_needed:
				continue
		_build_chunk(target, detail_needed)

	# Vegetation receives its own incremental queue. Small, independent patches
	# limit both CPU generation cost and Godot MultiMesh all-or-none culling.
	for _i in range(GRASS_PATCHES_PER_FRAME):
		if pending_grass_patches.is_empty():
			break
		var patch_coord: Vector2i = pending_grass_patches.pop_front()
		if grass_patches.has(patch_coord):
			continue
		var ring := maxi(absi(patch_coord.x - grass_patch_center.x), absi(patch_coord.y - grass_patch_center.y))
		if ring > GRASS_PATCH_RADIUS:
			continue
		_build_grass_patch(patch_coord)

func _schedule_missing_tiles() -> void:
	# Cancel work queued around the old player position.
	pending_chunks.clear()
	var expired: Array[Vector2i] = []
	for key in chunks.keys():
		var coord: Vector2i = key
		if maxi(absi(coord.x - player_tile.x), absi(coord.y - player_tile.y)) > HORIZON_RADIUS:
			expired.append(coord)
	for coord in expired:
		var entry: Dictionary = chunks[coord]
		(entry["node"] as Node3D).queue_free()
		chunks.erase(coord)
	# Prioritize the nearest tiles; collision must always be ready before
	# their far-off horizon decorations.
	for radius in range(HORIZON_RADIUS + 1):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var coord := player_tile + Vector2i(dx, dz)
				var needs_detail := radius <= DETAIL_RADIUS
				if chunks.has(coord):
					var entry: Dictionary = chunks[coord]
					if bool(entry["detail"]) or not needs_detail:
						continue
				pending_chunks.append(coord)

func _build_chunk(coord: Vector2i, detailed: bool) -> void:
	# Create the replacement BEFORE disposing of the old tile. At speed, the
	# character should never find a hole in the collidable surface.
	var tile := Node3D.new()
	tile.name = "Meadow_tile_%d_%d" % [coord.x, coord.y]
	tile.position = Vector3(float(coord.x) * CHUNK_SIZE, 0, float(coord.y) * CHUNK_SIZE)
	add_child(tile)
	var mesh := _terrain_mesh_for(coord, NEAR_SUBDIVISIONS if detailed else FAR_SUBDIVISIONS)
	var visual := MeshInstance3D.new()
	visual.name = "Meadow_surface"
	visual.mesh = mesh
	visual.material_override = terrain_material
	tile.add_child(visual)
	if detailed:
		var body := StaticBody3D.new()
		body.name = "Solid_meadow"
		tile.add_child(body)
		var collider := CollisionShape3D.new()
		collider.shape = mesh.create_trimesh_shape()
		body.add_child(collider)
		_add_grass(tile, coord)
		_add_trees(tile, coord)
		_add_flowers(tile, coord)
		_add_stones_and_shrubs(tile, coord)
	if chunks.has(coord):
		var previous: Dictionary = chunks[coord]
		(previous["node"] as Node3D).queue_free()
	chunks[coord] = {"node": tile, "detail": detailed}

func _terrain_mesh_for(coord: Vector2i, subdivisions: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := CHUNK_SIZE / float(subdivisions)
	var local_start := -CHUNK_SIZE * 0.5
	var offset_x := float(coord.x) * CHUNK_SIZE
	var offset_z := float(coord.y) * CHUNK_SIZE
	# A tile's geometry is centred on its chunk coordinate. This ensures all
	# tile boundaries are at (coordinate +/- 0.5)*CHUNK_SIZE.
	for zi in range(subdivisions):
		var z0 := local_start + zi * step
		var z1 := z0 + step
		for xi in range(subdivisions):
			var x0 := local_start + xi * step
			var x1 := x0 + step
			var a := Vector3(x0, height_at(offset_x + x0, offset_z + z0), z0)
			var b := Vector3(x1, height_at(offset_x + x1, offset_z + z0), z0)
			var c := Vector3(x0, height_at(offset_x + x0, offset_z + z1), z1)
			var d := Vector3(x1, height_at(offset_x + x1, offset_z + z1), z1)
			# Same upward-facing winding as the working v0.4 solid-meadow fix.
			_add_terrain_vertex(st, a, offset_x, offset_z)
			_add_terrain_vertex(st, b, offset_x, offset_z)
			_add_terrain_vertex(st, c, offset_x, offset_z)
			_add_terrain_vertex(st, b, offset_x, offset_z)
			_add_terrain_vertex(st, d, offset_x, offset_z)
			_add_terrain_vertex(st, c, offset_x, offset_z)
	st.index()
	return st.commit()

func _add_terrain_vertex(st: SurfaceTool, local: Vector3, offset_x: float, offset_z: float) -> void:
	var x := local.x + offset_x
	var z := local.z + offset_z
	st.set_normal(surface_normal_at(x, z))
	st.set_uv(Vector2(x * 0.03, z * 0.03))
	st.add_vertex(local)

func _tile_rng(coord: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absi((coord.x * 73856093) ^ (coord.y * 19349663))) + 103127
	return rng

func _build_near_grass() -> void:
	# Patches are fixed to world-space grid cells, never teleported with the
	# player. This eliminates the moving-square effect at high velocity.
	grass_patches_root = Node3D.new()
	grass_patches_root.name = "Streamed_flowing_meadow"
	add_child(grass_patches_root)
	grass_patch_center = Vector2i.ZERO
	# Guarantee good close-up grass on the very first frame.
	for z in range(-1, 2):
		for x in range(-1, 2):
			_build_grass_patch(Vector2i(x, z))
	_schedule_grass_patches()

func _update_near_grass(player_position: Vector3, movement_velocity: Vector3) -> void:
	if grass_patches_root == null:
		return
	# Anticipate where a fast runner will be ~1.5 seconds from now. We still
	# retain a wide ring behind the actual player for camera turns/jumps.
	var planar_velocity := Vector2(movement_velocity.x, movement_velocity.z)
	var advance := Vector2.ZERO
	var speed := planar_velocity.length()
	if speed > 0.5:
		advance = planar_velocity.normalized() * minf(speed * GRASS_LOOKAHEAD_SECONDS, GRASS_MAX_LOOKAHEAD)
	var center := Vector2i(
		floori((player_position.x + advance.x) / GRASS_PATCH_SIZE),
		floori((player_position.z + advance.y) / GRASS_PATCH_SIZE)
	)
	if center == grass_patch_center:
		return
	grass_patch_center = center
	_schedule_grass_patches()

func _schedule_grass_patches() -> void:
	pending_grass_patches.clear()
	# Retain one ring of existing patches as a hysteresis buffer: turning the
	# camera or changing direction should not destroy freshly rendered grass.
	var expired: Array[Vector2i] = []
	for key in grass_patches.keys():
		var coord: Vector2i = key
		if maxi(absi(coord.x - grass_patch_center.x), absi(coord.y - grass_patch_center.y)) > GRASS_PATCH_RADIUS + 1:
			expired.append(coord)
	for coord in expired:
		var instance: MultiMeshInstance3D = grass_patches[coord]
		instance.queue_free()
		grass_patches.erase(coord)
	# Always build nearest grass first. Newly entering far patches are hundreds
	# of metres away, so no pop-in occurs under the player's feet.
	for radius in range(GRASS_PATCH_RADIUS + 1):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var coord := grass_patch_center + Vector2i(dx, dz)
				if not grass_patches.has(coord):
					pending_grass_patches.append(coord)

func _build_grass_patch(coord: Vector2i) -> void:
	var patch := MultiMeshInstance3D.new()
	patch.name = "Grass_patch_%d_%d" % [coord.x, coord.y]
	patch.position = Vector3(float(coord.x) * GRASS_PATCH_SIZE, 0.0, float(coord.y) * GRASS_PATCH_SIZE)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = grass_mesh
	mm.instance_count = GRASS_PATCH_INSTANCES
	# The grass sits on hills between about -45 and 45 m. Explicit local bounds
	# prevent a whole MultiMesh patch disappearing when the camera turns.
	mm.custom_aabb = AABB(Vector3(-2.0, -85.0, -2.0), Vector3(GRASS_PATCH_SIZE + 4.0, 170.0, GRASS_PATCH_SIZE + 4.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absi((coord.x * 92837111) ^ (coord.y * 689287499))) + 79017
	var ox := float(coord.x) * GRASS_PATCH_SIZE
	var oz := float(coord.y) * GRASS_PATCH_SIZE
	for i in range(GRASS_PATCH_INSTANCES):
		var x := rng.randf_range(0.0, GRASS_PATCH_SIZE)
		var z := rng.randf_range(0.0, GRASS_PATCH_SIZE)
		var world_x := ox + x
		var world_z := oz + z
		var y := height_at(world_x, world_z) + 0.035
		var orientation := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		var scale_factor := rng.randf_range(0.76, 1.29)
		orientation = orientation.scaled(Vector3(scale_factor, rng.randf_range(0.66, 1.40), scale_factor))
		mm.set_instance_transform(i, Transform3D(orientation, Vector3(x, y, z)))
		var meadow_variation := rng.randf_range(0.83, 1.13)
		mm.set_instance_color(i, Color(meadow_variation * 0.89, meadow_variation * 1.02, meadow_variation * 0.79))
	mm.visible_instance_count = GRASS_PATCH_INSTANCES if dense_grass_enabled else int(GRASS_PATCH_INSTANCES * 0.38)
	patch.multimesh = mm
	grass_patches_root.add_child(patch)
	grass_patches[coord] = patch

func _add_grass(tile: Node3D, coord: Vector2i) -> void:
	var rng := _tile_rng(coord)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = grass_mesh
	mm.instance_count = GRASS_PER_TILE
	var ox := float(coord.x) * CHUNK_SIZE
	var oz := float(coord.y) * CHUNK_SIZE
	for i in range(GRASS_PER_TILE):
		var local_x := rng.randf_range(-CHUNK_SIZE * 0.49, CHUNK_SIZE * 0.49)
		var local_z := rng.randf_range(-CHUNK_SIZE * 0.49, CHUNK_SIZE * 0.49)
		var y := height_at(ox + local_x, oz + local_z) + 0.015
		var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		var size_factor := rng.randf_range(0.60, 1.24)
		turn = turn.scaled(Vector3(size_factor, rng.randf_range(0.60, 1.38), size_factor))
		mm.set_instance_transform(i, Transform3D(turn, Vector3(local_x, y, local_z)))
		var shade := rng.randf_range(0.83, 1.11)
		mm.set_instance_color(i, Color(shade * 0.90, shade, shade * 0.80))
	var foliage := MultiMeshInstance3D.new()
	foliage.name = "Meadow_grass"
	foliage.multimesh = mm
	mm.visible_instance_count = GRASS_PER_TILE if dense_grass_enabled else int(GRASS_PER_TILE * 0.40)
	foliage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tile.add_child(foliage)

func toggle_grass_density() -> bool:
	dense_grass_enabled = not dense_grass_enabled
	for patch in grass_patches.values():
		var patch_instance: MultiMeshInstance3D = patch
		patch_instance.multimesh.visible_instance_count = GRASS_PATCH_INSTANCES if dense_grass_enabled else int(GRASS_PATCH_INSTANCES * 0.38)
	for entry in chunks.values():
		var entry_dict: Dictionary = entry
		var node := entry_dict["node"] as Node3D
		var grass := node.get_node_or_null("Meadow_grass") as MultiMeshInstance3D
		if grass != null and grass.multimesh != null:
			grass.multimesh.visible_instance_count = GRASS_PER_TILE if dense_grass_enabled else int(GRASS_PER_TILE * 0.40)
		var flowers := node.get_node_or_null("Wildflower_clusters") as MultiMeshInstance3D
		if flowers != null and flowers.multimesh != null:
			flowers.multimesh.visible_instance_count = FLOWERS_PER_TILE if dense_grass_enabled else int(FLOWERS_PER_TILE * 0.5)
		var stones := node.get_node_or_null("Mossy_limestone") as MultiMeshInstance3D
		if stones != null and stones.multimesh != null:
			stones.multimesh.visible_instance_count = STONES_PER_TILE if dense_grass_enabled else int(STONES_PER_TILE * 0.65)
		var shrubs := node.get_node_or_null("Soft_meadow_shrubs") as MultiMeshInstance3D
		if shrubs != null and shrubs.multimesh != null:
			shrubs.multimesh.visible_instance_count = SHRUBS_PER_TILE if dense_grass_enabled else int(SHRUBS_PER_TILE * 0.45)
	return dense_grass_enabled

func _add_flowers(tile: Node3D, coord: Vector2i) -> void:
	# Patch-based wildflowers create recognizable islands of color without
	# building large flower meshes. Deterministic per tile to avoid flicker.
	var rng := _tile_rng(coord)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = flower_mesh
	mm.instance_count = FLOWERS_PER_TILE
	var centers: Array[Vector2] = []
	for j in range(14):
		centers.append(Vector2(rng.randf_range(-95.0, 95.0), rng.randf_range(-95.0, 95.0)))
	var ox := float(coord.x) * CHUNK_SIZE
	var oz := float(coord.y) * CHUNK_SIZE
	for i in range(FLOWERS_PER_TILE):
		var center: Vector2 = centers[i % centers.size()]
		var local_x := clampf(center.x + rng.randfn(0.0, 8.0), -108.0, 108.0)
		var local_z := clampf(center.y + rng.randfn(0.0, 8.0), -108.0, 108.0)
		var ground_y := height_at(ox + local_x, oz + local_z)
		var rotation_basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		var flower_scale := rng.randf_range(0.57, 1.30)
		rotation_basis = rotation_basis.scaled(Vector3.ONE * flower_scale)
		mm.set_instance_transform(i, Transform3D(rotation_basis, Vector3(local_x, ground_y + 0.03, local_z)))
		var palette_pick := rng.randi_range(0, 4)
		var flower_color := Color("fff5d7")
		if palette_pick == 1:
			flower_color = Color("e9b7cb")
		elif palette_pick == 2:
			flower_color = Color("d9d3ff")
		elif palette_pick == 3:
			flower_color = Color("f7d37c")
		elif palette_pick == 4:
			flower_color = Color("e4f2fb")
		mm.set_instance_color(i, flower_color)
	mm.visible_instance_count = FLOWERS_PER_TILE if dense_grass_enabled else int(FLOWERS_PER_TILE * 0.45)
	var display := MultiMeshInstance3D.new()
	display.name = "Wildflower_clusters"
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	display.multimesh = mm
	tile.add_child(display)

func _add_trees(tile: Node3D, coord: Vector2i) -> void:
	var rng := _tile_rng(coord)
	var trunks := MultiMesh.new()
	trunks.transform_format = MultiMesh.TRANSFORM_3D
	trunks.mesh = trunk_mesh
	trunks.instance_count = TREES_PER_TILE
	var canopies := MultiMesh.new()
	canopies.transform_format = MultiMesh.TRANSFORM_3D
	canopies.use_colors = true
	canopies.mesh = foliage_mesh
	canopies.instance_count = TREES_PER_TILE * 7
	# Lightweight angled branches improve silhouettes at walking distance.
	var branches := MultiMesh.new()
	branches.transform_format = MultiMesh.TRANSFORM_3D
	branches.mesh = branch_mesh
	branches.instance_count = TREES_PER_TILE * 3
	var ox := float(coord.x) * CHUNK_SIZE
	var oz := float(coord.y) * CHUNK_SIZE
	for i in range(TREES_PER_TILE):
		var x := rng.randf_range(-CHUNK_SIZE * 0.45, CHUNK_SIZE * 0.45)
		var z := rng.randf_range(-CHUNK_SIZE * 0.45, CHUNK_SIZE * 0.45)
		# Don't clutter the central spawn point.
		if absf(ox + x) < 22.0 and absf(oz + z) < 22.0:
			x += 35.0
		var y := height_at(ox + x, oz + z)
		var scale_factor := rng.randf_range(0.85, 1.40)
		var tree_pos := Vector3(x, y, z)
		for branch_i in range(3):
			var azimuth := float(branch_i) * TAU / 3.0 + float(i) * 0.63
			var root_point := tree_pos + Vector3(0.0, 2.70 * scale_factor, 0.0)
			var tip_point := tree_pos + Vector3(cos(azimuth) * 2.15, 4.90, sin(azimuth) * 2.15) * scale_factor
			var shaft := tip_point - root_point
			var aligned := Basis(Quaternion(Vector3.UP, shaft.normalized()))
			var taper := aligned.scaled(Vector3(scale_factor * 0.82, shaft.length(), scale_factor * 0.82))
			branches.set_instance_transform(i * 3 + branch_i, Transform3D(taper, (root_point + tip_point) * 0.5))
		var scale_basis := Basis.IDENTITY.scaled(Vector3.ONE * scale_factor)
		trunks.set_instance_transform(i, Transform3D(scale_basis, tree_pos + Vector3.UP * (2.0 * scale_factor)))
		for crown_i in range(7):
			var crown_index := i * 7 + crown_i
			var angle := float(crown_i) * TAU / 6.0 + float(i) * 0.7
			var radius := 1.6 if crown_i < 6 else 0.0
			var vertical := 5.2 + float(crown_i % 3) * 0.36 if crown_i < 6 else 6.35
			var crown_pos := tree_pos + Vector3(cos(angle) * radius * scale_factor, vertical * scale_factor, sin(angle) * radius * scale_factor)
			var crown_scale := scale_basis.scaled(Vector3(rng.randf_range(0.68, 0.92), rng.randf_range(0.68, 0.99), rng.randf_range(0.68, 0.95)))
			canopies.set_instance_transform(crown_index, Transform3D(crown_scale, crown_pos))
			var tone := rng.randf_range(0.82, 1.06)
			canopies.set_instance_color(crown_index, Color(tone * 0.67, tone * 0.82, tone * 0.57))
		# Keep tree collisions limited to the trunk, never the entire crown.
		var obstacle := StaticBody3D.new()
		obstacle.position = tree_pos
		tile.add_child(obstacle)
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.48 * scale_factor
		cylinder.height = 4.0 * scale_factor
		shape.shape = cylinder
		shape.position.y = 2.0 * scale_factor
		obstacle.add_child(shape)
	var branch_nodes := MultiMeshInstance3D.new()
	branch_nodes.name = "Tree_branches"
	branch_nodes.multimesh = branches
	tile.add_child(branch_nodes)
	var trunk_nodes := MultiMeshInstance3D.new()
	trunk_nodes.name = "Sparse_trunks"
	trunk_nodes.multimesh = trunks
	tile.add_child(trunk_nodes)
	var canopy_nodes := MultiMeshInstance3D.new()
	canopy_nodes.name = "Rounded_tree_canopies"
	canopy_nodes.multimesh = canopies
	tile.add_child(canopy_nodes)

func _add_stones_and_shrubs(tile: Node3D, coord: Vector2i) -> void:
	# A few mossy limestone rocks and low shrubs help sell scale and reduce the
	# repeating lawn appearance. No physics is added to these small props.
	var rng := _tile_rng(coord)
	var origin_x := float(coord.x) * CHUNK_SIZE
	var origin_z := float(coord.y) * CHUNK_SIZE
	var stones := MultiMesh.new()
	stones.transform_format = MultiMesh.TRANSFORM_3D
	stones.use_colors = true
	stones.mesh = stone_mesh
	stones.instance_count = STONES_PER_TILE
	for i in range(STONES_PER_TILE):
		var x := rng.randf_range(-103.0, 103.0)
		var z := rng.randf_range(-103.0, 103.0)
		var y := height_at(origin_x + x, origin_z + z)
		var shape := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		shape = shape.scaled(Vector3(rng.randf_range(0.55, 1.38), rng.randf_range(0.25, 0.64), rng.randf_range(0.47, 1.25)))
		stones.set_instance_transform(i, Transform3D(shape, Vector3(x, y + 0.05, z)))
		var tone := rng.randf_range(0.80, 1.10)
		stones.set_instance_color(i, Color(tone * 0.67, tone * 0.73, tone * 0.60))
	stones.visible_instance_count = STONES_PER_TILE if dense_grass_enabled else int(STONES_PER_TILE * 0.65)
	var stone_node := MultiMeshInstance3D.new()
	stone_node.name = "Mossy_limestone"
	stone_node.multimesh = stones
	stone_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tile.add_child(stone_node)

	var shrubs := MultiMesh.new()
	shrubs.transform_format = MultiMesh.TRANSFORM_3D
	shrubs.use_colors = true
	shrubs.mesh = shrub_mesh
	shrubs.instance_count = SHRUBS_PER_TILE
	for i in range(SHRUBS_PER_TILE):
		var x := rng.randf_range(-101.0, 101.0)
		var z := rng.randf_range(-101.0, 101.0)
		var y := height_at(origin_x + x, origin_z + z)
		var spin := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		spin = spin.scaled(Vector3(rng.randf_range(0.42, 0.95), rng.randf_range(0.26, 0.65), rng.randf_range(0.42, 0.98)))
		shrubs.set_instance_transform(i, Transform3D(spin, Vector3(x, y + 0.12, z)))
		var tone := rng.randf_range(0.87, 1.08)
		shrubs.set_instance_color(i, Color(tone * 0.43, tone * 0.79, tone * 0.31))
	shrubs.visible_instance_count = SHRUBS_PER_TILE if dense_grass_enabled else int(SHRUBS_PER_TILE * 0.45)
	var shrub_node := MultiMeshInstance3D.new()
	shrub_node.name = "Soft_meadow_shrubs"
	shrub_node.multimesh = shrubs
	shrub_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tile.add_child(shrub_node)

func _create_shared_meshes_and_materials() -> void:
	# v1.2 materials are editable shader resources rather than giant inline strings.
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = load("res://shaders/meadow_ground.gdshader") as Shader
	terrain_material.set_shader_parameter("meadow_brush", load("res://assets/meadow_brush.png"))

	# Soft silhouette from illustrated alpha-clipped clumps. Two crossed cards per
	# tuft are cheaper than the old 12-triangle pointed geometric spikes.
	var grass_surface := SurfaceTool.new()
	grass_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane_index in range(2):
		var angle := float(plane_index) * PI * 0.5 + 0.22
		var right := Vector3(cos(angle), 0.0, sin(angle)) * 0.66
		var bow := Vector3(-sin(angle), 0.0, cos(angle)) * 0.10
		var top := Vector3.UP * 1.04 + bow
		_add_card_vertex(grass_surface, -right, Vector2(0, 1))
		_add_card_vertex(grass_surface, right, Vector2(1, 1))
		_add_card_vertex(grass_surface, top - right, Vector2(0, 0))
		_add_card_vertex(grass_surface, right, Vector2(1, 1))
		_add_card_vertex(grass_surface, top + right, Vector2(1, 0))
		_add_card_vertex(grass_surface, top - right, Vector2(0, 0))
	grass_surface.generate_normals()
	grass_mesh = grass_surface.commit()
	var grass_material := ShaderMaterial.new()
	grass_material.shader = load("res://shaders/grass_cards.gdshader") as Shader
	grass_material.set_shader_parameter("painted_grass", load("res://assets/grass_painterly.png"))
	grass_mesh.surface_set_material(0, grass_material)

	trunk_mesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.32
	trunk_mesh.bottom_radius = 0.49
	trunk_mesh.height = 4.0
	trunk_mesh.radial_segments = 12
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color("70533b")
	bark.roughness = 1.0
	trunk_mesh.material = bark
	branch_mesh = CylinderMesh.new()
	branch_mesh.top_radius = 0.075
	branch_mesh.bottom_radius = 0.16
	branch_mesh.height = 1.0
	branch_mesh.radial_segments = 7
	branch_mesh.material = bark
	foliage_mesh = SphereMesh.new()
	foliage_mesh.radius = 2.9
	foliage_mesh.height = 5.5
	foliage_mesh.radial_segments = 20
	foliage_mesh.rings = 11
	foliage_material = StandardMaterial3D.new()
	foliage_material.albedo_color = Color("75a65b")
	foliage_material.roughness = 1.0
	# Tree color and irregular leaf shading are supplied by the material on
	# the shared mesh, with per-instance colors coming from MultiMesh.
	var crowns := ShaderMaterial.new()
	crowns.shader = load("res://shaders/leaf_crowns.gdshader") as Shader
	foliage_mesh.material = crowns

	stone_mesh = SphereMesh.new()
	stone_mesh.radius = 0.88
	stone_mesh.height = 1.4
	stone_mesh.radial_segments = 10
	stone_mesh.rings = 6
	var stone_material := StandardMaterial3D.new()
	stone_material.vertex_color_use_as_albedo = true
	stone_material.roughness = 1.0
	stone_mesh.material = stone_material

	shrub_mesh = SphereMesh.new()
	shrub_mesh.radius = 1.15
	shrub_mesh.height = 1.65
	shrub_mesh.radial_segments = 11
	shrub_mesh.rings = 6
	var shrub_material := StandardMaterial3D.new()
	shrub_material.vertex_color_use_as_albedo = true
	shrub_material.roughness = 1.0
	shrub_mesh.material = shrub_material

	var flowers := SurfaceTool.new()
	flowers.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane_index in range(2):
		var angle := float(plane_index) * PI * 0.5
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.48
		_add_card_vertex(flowers, -offset, Vector2(0, 1))
		_add_card_vertex(flowers, offset, Vector2(1, 1))
		_add_card_vertex(flowers, Vector3.UP * 0.98 - offset, Vector2(0, 0))
		_add_card_vertex(flowers, offset, Vector2(1, 1))
		_add_card_vertex(flowers, Vector3.UP * 0.98 + offset, Vector2(1, 0))
		_add_card_vertex(flowers, Vector3.UP * 0.98 - offset, Vector2(0, 0))
	flowers.generate_normals()
	flower_mesh = flowers.commit()
	var flower_mat := ShaderMaterial.new()
	flower_mat.shader = load("res://shaders/flower_cards.gdshader") as Shader
	flower_mat.set_shader_parameter("painted_flowers", load("res://assets/wildflowers_painterly.png"))
	flower_mesh.surface_set_material(0, flower_mat)

func _add_card_vertex(st: SurfaceTool, position: Vector3, texcoord: Vector2) -> void:
	st.set_uv(texcoord)
	st.add_vertex(position)

func _build_clouds() -> void:
	# Billboard cloud banks supply a reliable, visible layer in the sky even
	# when a panorama cloud happens to lie above the camera's sightline.
	clouds_root = Node3D.new()
	clouds_root.name = "Distant_painted_clouds"
	add_child(clouds_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19022
	var tex := load("res://assets/cloud_banks.png") as Texture2D
	for i in range(18):
		var angle := TAU * float(i) / 18.0 + rng.randf_range(-0.16, 0.16)
		var distance := rng.randf_range(310.0, 660.0)
		var sprite := Sprite3D.new()
		sprite.name = "Cloud_bank_%02d" % i
		sprite.texture = tex
		sprite.pixel_size = rng.randf_range(0.31, 0.48)
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.transparent = true
		sprite.position = Vector3(sin(angle) * distance, rng.randf_range(95.0, 178.0), cos(angle) * distance)
		sprite.no_depth_test = false
		clouds_root.add_child(sprite)

func _build_lighting() -> void:
	# Panoramic skies are pre-painted assets: no runtime cloud geometry needed.
	daylight_sky = load("res://assets/sky_day.jpg") as Texture2D
	sunset_sky = load("res://assets/sky_golden.jpg") as Texture2D
	meadow_sky = PanoramaSkyMaterial.new()
	meadow_sky.panorama = daylight_sky
	var sky := Sky.new()
	sky.sky_material = meadow_sky
	var env := Environment.new()
	meadow_env = env
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.64
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("9cbfca")
	env.fog_density = 0.00064
	var environment := WorldEnvironment.new()
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun_light = sun
	sun.light_color = Color("fff0d6")
	sun.light_energy = 0.98
	sun.rotation_degrees = Vector3(-44.0, -40.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

func set_golden_hour(enabled: bool) -> void:
	golden_hour = enabled
	if meadow_sky == null or meadow_env == null or sun_light == null:
		return
	if golden_hour:
		meadow_sky.panorama = sunset_sky
		meadow_env.fog_light_color = Color("efcdb4")
		meadow_env.fog_density = 0.00078
		sun_light.light_color = Color("ffd0a0")
		sun_light.light_energy = 1.05
		sun_light.rotation_degrees = Vector3(-21.0, -54.0, 0.0)
		if clouds_root != null:
			for child in clouds_root.get_children():
				(child as Sprite3D).modulate = Color("ffe0c4")
	else:
		meadow_sky.panorama = daylight_sky
		meadow_env.fog_light_color = Color("9cbfca")
		meadow_env.fog_density = 0.00064
		sun_light.light_color = Color("fff0d6")
		sun_light.light_energy = 0.98
		sun_light.rotation_degrees = Vector3(-44.0, -40.0, 0.0)
		if clouds_root != null:
			for child in clouds_root.get_children():
				(child as Sprite3D).modulate = Color.WHITE
