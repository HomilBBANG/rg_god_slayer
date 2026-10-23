## Blender 에서 만든 glTF 에셋을 씬에 놓고, glTF 머티리얼 이름 → RED 셰이더 머티리얼로 치환하는 도우미.
## 충돌은 종류별로: 바위/기둥/블록 = 메시 볼록 껍질, 나무 = 줄기 실린더, 덤불 = 없음.
class_name EnvAssets
extends RefCounted

const SCENES := {
	"tree_a": preload("res://assets/environment/tree_a.glb"),
	"tree_b": preload("res://assets/environment/tree_b.glb"),
	"rock_a": preload("res://assets/environment/rock_a.glb"),
	"rock_b": preload("res://assets/environment/rock_b.glb"),
	"rock_c": preload("res://assets/environment/rock_c.glb"),
	"rock_d": preload("res://assets/environment/rock_d.glb"),
	"bush_a": preload("res://assets/environment/bush_a.glb"),
	"bush_b": preload("res://assets/environment/bush_b.glb"),
	"pillar_a": preload("res://assets/environment/pillar_a.glb"),
	"pillar_b": preload("res://assets/environment/pillar_b.glb"),
	"block_a": preload("res://assets/environment/block_a.glb"),
	"block_b": preload("res://assets/environment/block_b.glb"),
	"wall_low_a": preload("res://assets/environment/wall_low_a.glb"),
	"wall_low_b": preload("res://assets/environment/wall_low_b.glb"),
	"wall_low_c": preload("res://assets/environment/wall_low_c.glb"),
	"wall_tall_a": preload("res://assets/environment/wall_tall_a.glb"),
	"wall_tall_b": preload("res://assets/environment/wall_tall_b.glb"),
}
const WALL_SEG_LEN := 2.0
const WALL_LOW_H := 1.1
const WALL_TALL_H := 2.75

## glTF 머티리얼 이름 → 셰이더 머티리얼
const MATERIALS := {
	"Leaf": preload("res://materials/mat_leaf.tres"),
	"Bark": preload("res://materials/mat_bark.tres"),
	"Rock": preload("res://materials/mat_rock.tres"),
	"Stone": preload("res://materials/mat_stone_lit.tres"),
	"Bush": preload("res://materials/mat_bush.tres"),
	"GrassCard": preload("res://materials/mat_grasscard.tres"),
	"Hair": preload("res://materials/mat_hair.tres"),
	"Skin": preload("res://materials/mat_skin.tres"),
	"Cloth": preload("res://materials/mat_cloth.tres"),
	"Belt": preload("res://materials/mat_belt.tres"),
	"Buckle": preload("res://materials/mat_buckle.tres"),
	"Shoe": preload("res://materials/mat_shoe.tres"),
}

const LAYER_WORLD := 1


static func spawn(parent: Node, kind: String, pos: Vector3, yaw_deg: float = 0.0, scale: float = 1.0, collide: bool = true) -> Node3D:
	var packed: PackedScene = SCENES[kind]
	var inst := packed.instantiate() as Node3D
	inst.name = kind
	inst.position = pos
	inst.rotation_degrees.y = yaw_deg
	inst.scale = Vector3.ONE * scale
	parent.add_child(inst)
	_apply_materials(inst)
	if collide:
		_add_collision(inst, kind)
	return inst


## 돌담: 박스 충돌 1개 + 2 m 블록 모듈을 길이만큼 타일. tall=true 면 5줄(2.75 m) 담.
## yaw 는 담의 길이 축(+X) 회전. 마지막 토막은 남은 길이에 맞춰 x 스케일.
static func wall(parent: Node, n: String, length: float, pos: Vector3, yaw_deg: float = 0.0, tall: bool = false, seed_value: int = 0) -> StaticBody3D:
	var h := WALL_TALL_H if tall else WALL_LOW_H
	var body := StaticBody3D.new()
	body.name = n
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	body.rotation_degrees.y = yaw_deg
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, h, 0.6)
	shape.shape = box
	shape.position = Vector3(0.0, h * 0.5, 0.0)
	body.add_child(shape)
	parent.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(n) + seed_value
	var variants := ["wall_tall_a", "wall_tall_b"] if tall else ["wall_low_a", "wall_low_b", "wall_low_c"]
	var x := -length * 0.5
	while x < length - 0.01 - length * 0.5:
		var seg_len := minf(WALL_SEG_LEN, length * 0.5 - x)
		var kind: String = variants[rng.randi() % variants.size()]
		var inst := SCENES[kind].instantiate() as Node3D
		inst.name = "Seg%d" % int((x + length * 0.5) / WALL_SEG_LEN)
		inst.position = Vector3(x + seg_len * 0.5, 0.0, 0.0)
		# 짝수 토막은 뒤집어 반복 패턴을 흐린다
		inst.rotation_degrees.y = 180.0 if rng.randf() < 0.5 else 0.0
		inst.scale = Vector3(seg_len / WALL_SEG_LEN, 1.0, 1.0)
		body.add_child(inst)
		_apply_materials(inst)
		x += seg_len
	return body


## glTF 머티리얼 이름으로 RED 머티리얼 치환 (외부에서도 사용: 플레이어 모델)
static func apply_materials(node: Node) -> void:
	_apply_materials(node)


static func _apply_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var mname := src.resource_name if src else ""
			if MATERIALS.has(mname):
				mi.set_surface_override_material(i, MATERIALS[mname])
			# 잎/풀 카드는 그림자를 드리우되 자기 그림자는 안 받는다 (셰이더에서 처리)
		if mname_of(mi) in ["Leaf", "GrassCard"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in node.get_children():
		_apply_materials(c)


static func mname_of(mi: MeshInstance3D) -> String:
	var src := mi.mesh.surface_get_material(0) if mi.mesh and mi.mesh.get_surface_count() > 0 else null
	return src.resource_name if src else ""


static func _add_collision(inst: Node3D, kind: String) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	if kind.begins_with("tree"):
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.32
		cyl.height = 2.0
		shape.shape = cyl
		shape.position = Vector3(0.0, 1.0, 0.0)
		body.add_child(shape)
	elif kind.begins_with("bush"):
		return
	else:
		# 첫 번째 MeshInstance3D 의 볼록 껍질
		var mi := _first_mesh(inst)
		if mi == null:
			return
		var shape := CollisionShape3D.new()
		shape.shape = mi.mesh.create_convex_shape(true, true)
		shape.transform = mi.transform
		body.add_child(shape)
	inst.add_child(body)


static func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r := _first_mesh(c)
		if r:
			return r
	return null
