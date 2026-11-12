extends Node3D
class_name WindLandmarks
## Three hand-built scenic destinations in the procedural endless meadow.
## Small number of static meshes; each destination hides when far away.

const DISCOVERY_RADIUS := 43.0
const DRAW_RADIUS := 1650.0

var world: MeadowWorld
var locations: Array[Dictionary] = [
	{"id": "whispering_oak", "name": "THE WHISPERING OAK", "position": Vector2(425.0, -620.0)},
	{"id": "skygate", "name": "THE SKYGATE", "position": Vector2(-820.0, -380.0)},
	{"id": "sunstone_circle", "name": "THE SUNSTONE CIRCLE", "position": Vector2(915.0, 610.0)}
]
var visited: Dictionary = {}
var landmark_roots: Array[Node3D] = []

func _ready() -> void:
	if world == null:
		push_warning("WINDRUN landmarks need a MeadowWorld reference")
		return
	for entry in locations:
		var point: Vector2 = entry["position"]
		var root := Node3D.new()
		root.name = str(entry["id"])
		root.position = Vector3(point.x, world.height_at(point.x, point.y), point.y)
		add_child(root)
		match str(entry["id"]):
			"whispering_oak":
				_make_giant_tree(root)
			"skygate":
				_make_skygate(root)
			"sunstone_circle":
				_make_sunstone_circle(root)
		landmark_roots.append(root)

func update_player(player_position: Vector3) -> String:
	var p := Vector2(player_position.x, player_position.z)
	var discovery := ""
	for i in range(locations.size()):
		var entry: Dictionary = locations[i]
		var point: Vector2 = entry["position"]
		var distance := p.distance_to(point)
		if i < landmark_roots.size():
			landmark_roots[i].visible = distance <= DRAW_RADIUS
		if distance <= DISCOVERY_RADIUS and not visited.has(str(entry["id"])):
			visited[str(entry["id"])] = true
			discovery = str(entry["name"])
	return discovery

func get_nearest_unvisited(player_position: Vector3) -> Dictionary:
	var player_2d := Vector2(player_position.x, player_position.z)
	var found: Dictionary = {}
	var closest := INF
	for entry in locations:
		if visited.has(str(entry["id"])):
			continue
		var point: Vector2 = entry["position"]
		var distance := point.distance_to(player_2d)
		if distance < closest:
			closest = distance
			found = {"name": str(entry["name"]), "position": point, "distance": distance}
	return found

func get_visited_ids() -> Array[String]:
	var result: Array[String] = []
	for entry in locations:
		var id := str(entry["id"])
		if visited.has(id):
			result.append(id)
	return result

func restore_visited(value: Array) -> void:
	visited.clear()
	for id in value:
		for entry in locations:
			if str(entry["id"]) == str(id):
				visited[str(id)] = true
				break

func count_visited() -> int:
	return visited.size()

func count_total() -> int:
	return locations.size()

func _solid_material(hex_color: String, roughness: float = 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex_color)
	m.roughness = roughness
	return m

func _mesh(parent: Node3D, name_text: String, mesh: PrimitiveMesh, material: Material, pos: Vector3, scale_v: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = name_text
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	part.scale = scale_v
	parent.add_child(part)
	return part

func _sphere(parent: Node3D, name_text: String, pos: Vector3, size: Vector3, material: Material) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 7
	_mesh(parent, name_text, sphere, material, pos, size)

func _rock(parent: Node3D, name_text: String, pos: Vector3, size: Vector3, material: Material, angle_deg: float = 0.0) -> void:
	var cube := BoxMesh.new()
	cube.size = size
	var piece := _mesh(parent, name_text, cube, material, pos)
	piece.rotation_degrees.z = angle_deg

func _branch(parent: Node3D, name_text: String, a: Vector3, b: Vector3, thickness: float, material: Material) -> void:
	var vector := b - a
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = thickness * 0.72
	cylinder.bottom_radius = thickness
	cylinder.height = vector.length()
	cylinder.radial_segments = 9
	var piece := _mesh(parent, name_text, cylinder, material, (a + b) * 0.5)
	piece.quaternion = Quaternion(Vector3.UP, vector.normalized())

func _trunk_collision(parent: Node3D, height: float, radius: float) -> void:
	var obstacle := StaticBody3D.new()
	parent.add_child(obstacle)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	col.position.y = height * 0.5
	obstacle.add_child(col)

func _make_giant_tree(root: Node3D) -> void:
	var bark := _solid_material("775737")
	var canopy_a := _solid_material("4f9b38")
	var canopy_b := _solid_material("70c74a")
	var canopy_c := _solid_material("99dc60")
	# Towering, friendly silhouette, visible over the rolling hills from afar.
	_branch(root, "Monumental_trunk", Vector3.ZERO, Vector3(0.0, 22.0, 0.0), 3.1, bark)
	_trunk_collision(root, 23.0, 2.55)
	var directions := [
		Vector3(-12, 20, 0), Vector3(10, 23, 1), Vector3(3, 22, -11),
		Vector3(-4, 24, 12), Vector3(-9, 29, -7), Vector3(8, 29, 8)
	]
	for i in range(directions.size()):
		_branch(root, "Wide_branch_%d" % i, Vector3(0, 15.0 + (i % 2) * 2.0, 0), directions[i], 1.1, bark)
	_sphere(root, "Core_foliage", Vector3(0, 29, 0), Vector3(12, 9.0, 11), canopy_a)
	for i in range(directions.size()):
		var p: Vector3 = directions[i]
		var materials := [canopy_a, canopy_b, canopy_c]
		_sphere(root, "Foliage_mass_%d" % i, p + Vector3(0, 3.0, 0), Vector3(8.0 + (i%3), 6.0, 7.5), materials[i % 3])
	_sphere(root, "Sunlit_crown", Vector3(0, 36, 1), Vector3(10, 6.2, 10), canopy_b)
	# A quiet ring of smooth stones to make the location feel intentional.
	var stone := _solid_material("acb9a0")
	for i in range(12):
		var a := TAU * float(i) / 12.0
		var x := cos(a) * 21.0
		var z := sin(a) * 21.0
		var gy := world.height_at(root.position.x + x, root.position.z + z) - root.position.y
		_rock(root, "Old_root_stone_%d" % i, Vector3(x, gy+0.8, z), Vector3(2.6, 1.5, 2.0), stone, sin(a*4.0)*9.0)

func _make_skygate(root: Node3D) -> void:
	var granite := _solid_material("a7b7aa")
	var granite_light := _solid_material("c5c9ad")
	var shadow_stone := _solid_material("85998b")
	for arch_idx in range(3):
		var depth := float(arch_idx - 1) * 16.0
		var height := 14.0 + float(1 - abs(arch_idx - 1)) * 3.0
		var span := 10.0
		var gy_left := world.height_at(root.position.x - span, root.position.z + depth) - root.position.y
		var gy_right := world.height_at(root.position.x + span, root.position.z + depth) - root.position.y
		_rock(root, "Skygate_left_%d" % arch_idx, Vector3(-span, height*0.5 + gy_left, depth), Vector3(3.0, height, 4.0), granite, -4.0)
		_rock(root, "Skygate_right_%d" % arch_idx, Vector3(span, height*0.5 + gy_right, depth), Vector3(3.0, height, 4.0), granite_light, 4.0)
		# Curved arch stones, not the old horizontal floating rectangular lintel.
		# The partial circle is a distinct silhouette on distant ridgelines.
		for stone_i in range(11):
			var theta_a := PI - float(stone_i) * PI / 11.0
			var theta_b := PI - float(stone_i+1) * PI / 11.0
			var a := Vector3(cos(theta_a)*span, height+sin(theta_a)*span, depth)
			var b := Vector3(cos(theta_b)*span, height+sin(theta_b)*span, depth)
			var segment := b-a
			var arch_block := _mesh(root, "Curved_arch_stone_%d_%d" % [arch_idx, stone_i], BoxMesh.new(),
				granite_light if stone_i % 4 == 0 else shadow_stone, (a+b)*0.5)
			(arch_block.mesh as BoxMesh).size = Vector3(3.4,segment.length()*1.08,4.0)
			arch_block.quaternion = Quaternion(Vector3.UP,segment.normalized())
		# Small caps break up otherwise perfect blocky edges.
		_rock(root, "Cap_left_%d" % arch_idx, Vector3(-span, height + gy_left, depth), Vector3(4.5, 1.5, 5.0), granite_light)
		_rock(root, "Cap_right_%d" % arch_idx, Vector3(span, height + gy_right, depth), Vector3(4.5, 1.5, 5.0), granite_light)
	_rock(root, "Skygate_marker", Vector3(0, 1.5, 30), Vector3(2.3, 3.0, 2.3), granite_light, 8.0)

func _make_sunstone_circle(root: Node3D) -> void:
	var warm_rock := _solid_material("d2bf87")
	var cool_rock := _solid_material("b0ad95")
	var gold := _solid_material("eedb9d")
	var rng := RandomNumberGenerator.new()
	rng.seed = 39017
	for i in range(13):
		var a := TAU * float(i) / 13.0
		var x := cos(a) * 19.0
		var z := sin(a) * 19.0
		var height := rng.randf_range(5.0, 10.5)
		var local_ground := world.height_at(root.position.x + x, root.position.z + z) - root.position.y
		_rock(root, "Ancient_sunstone_%02d" % i, Vector3(x, local_ground + height*0.5, z), Vector3(2.4, height, 3.1), warm_rock if i % 3 == 0 else cool_rock, rng.randf_range(-12.0, 12.0))
	var altar_ground := world.height_at(root.position.x, root.position.z) - root.position.y
	_rock(root, "Central_altar", Vector3(0, altar_ground + 1.0, 0), Vector3(5, 2, 5), cool_rock)
	_sphere(root, "Sun_glow_sculpture", Vector3(0, altar_ground + 5.4, 0), Vector3(2.4, 2.4, 2.4), gold)
