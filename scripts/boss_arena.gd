## 보스 테스트 아레나: 평평한 돌 광장 + 둘레 풀밭 + 모서리 기둥 + 보이지 않는 경계벽.
## 안전 방향 도착점 검증(GDD §5)을 위해 동쪽에 낮은 돌담 하나를 둔다 (막힌 방향 테스트용).
class_name BossArena
extends Node3D

const MAT_STONE_LIT := preload("res://materials/mat_stone_lit.tres")
const MAT_TILE_DARK := preload("res://materials/mat_tile_dark.tres")
const MAT_GRASS := preload("res://materials/mat_grass_ground.tres")
const MAT_GROUND := preload("res://materials/mat_ground.tres")
const LAYER_WORLD := 1

## 광장 반폭 (m)
@export var half_size: float = 9.0
## 경계벽 반폭 (m)
@export var bound_x: float = 12.0
@export var bound_z: float = 9.5


func _ready() -> void:
	_box(self, "GroundOuter", Vector3(80, 0.2, 80), Vector3(0, -0.1, 0), MAT_GRASS, true)
	_box(self, "Plaza", Vector3(half_size * 2.0 + 2.0, 0.06, half_size * 2.0 + 2.0), Vector3(0, 0.0, 0), MAT_GROUND, false)
	var tiles := Node3D.new()
	tiles.name = "CheckerFloor"
	add_child(tiles)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var n := int(half_size)
	for ix in range(-n, n):
		for iz in range(-n, n):
			if rng.randf() < 0.06:
				continue
			var mat := MAT_STONE_LIT if (ix + iz) % 2 == 0 else MAT_TILE_DARK
			_box(tiles, "T%d_%d" % [ix, iz], Vector3(0.96, 0.07, 0.96), Vector3(ix + 0.5, 0.045, iz + 0.5), mat, false)
	var deco := Node3D.new()
	deco.name = "Deco"
	add_child(deco)
	for p in [Vector3(-half_size - 1.5, 0, -half_size - 1.5), Vector3(half_size + 1.5, 0, -half_size - 1.5), Vector3(-half_size - 1.5, 0, half_size + 1.5), Vector3(half_size + 1.5, 0, half_size + 1.5)]:
		EnvAssets.spawn(deco, "cap_pillar_a", p)
	EnvAssets.spawn(deco, "dead_tree_a", Vector3(-14.0, 0, -6.0))
	EnvAssets.spawn(deco, "birch_b", Vector3(14.5, 0, 5.0), 0.0, 0.9)
	EnvAssets.spawn(deco, "bush2_a", Vector3(-13.0, 0, 4.0))
	EnvAssets.spawn(deco, "rock_b", Vector3(12.5, 0, -8.0))
	# 동쪽 낮은 돌담 (도착점 막힘 테스트용): x=+8.5, z -3..+3
	EnvAssets.wall(deco, "WallEast", 6.0, Vector3(8.5, 0, 0), 90.0, false, 5)
	_boundary()


func _box(parent: Node, n: String, size: Vector3, pos: Vector3, mat: Material, collide: bool) -> Node3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = n
	if not collide:
		mi.position = pos
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.name = n
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.add_child(mi)
	parent.add_child(body)
	return body


func _boundary() -> void:
	var b := Node3D.new()
	b.name = "Boundary"
	add_child(b)
	var h := 3.0
	_wall(b, "N", Vector3(bound_x * 2.0 + 1.0, h, 0.5), Vector3(0, h * 0.5, -bound_z - 0.25))
	_wall(b, "S", Vector3(bound_x * 2.0 + 1.0, h, 0.5), Vector3(0, h * 0.5, bound_z + 0.25))
	_wall(b, "W", Vector3(0.5, h, bound_z * 2.0 + 1.0), Vector3(-bound_x - 0.25, h * 0.5, 0))
	_wall(b, "E", Vector3(0.5, h, bound_z * 2.0 + 1.0), Vector3(bound_x + 0.25, h * 0.5, 0))


func _wall(parent: Node, n: String, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Bound" + n
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
