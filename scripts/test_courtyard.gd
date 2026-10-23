## 테스트 맵 — 돌담이 있는 폐허 마을 안뜰 (GDD §8)
## 약 36×28m. 모든 환경 메시는 기본 프리미티브(Box/Cylinder/Plane)를 RED_FlatLit 머티리얼로 그린다.
## 텍스처/소품/풀 없음. 큰 색면만으로 공간을 읽게 하는 것이 목적.
##
## 동선: 중앙 광장(원점) → 동쪽 좁은 돌담 통로 → 북동쪽 계단/단차 → 공격 더미 공간
## 충돌 테스트: 돌담 다수, 계단(램프 충돌) 1개, 건물 모서리/입구.
extends Node3D

const MAT_STONE := preload("res://materials/mat_stone.tres")
const MAT_STONE_LIT := preload("res://materials/mat_stone_lit.tres")
const MAT_GROUND := preload("res://materials/mat_ground.tres")
const MAT_OLIVE := preload("res://materials/mat_olive.tres")
const MAT_OLIVE_LIGHT := preload("res://materials/mat_olive_light.tres")
const MAT_SLATE := preload("res://materials/mat_slate.tres")
const MAT_GRASS := preload("res://materials/mat_grass_ground.tres")
const MAT_ROOF := preload("res://materials/mat_roof.tres")
const MAT_TILE_DARK := preload("res://materials/mat_tile_dark.tres")

const LAYER_WORLD := 1

var roof: Node3D


func _ready() -> void:
	_build_ground()
	_build_plaza()
	_build_walls()
	_build_stairs_and_terrace()
	_build_ruin_building()
	_build_trees()
	_build_shadow_pillar()
	_build_details()
	_build_boundary()


# ---------------------------------------------------------------- helpers

func _box(parent: Node, n: String, size: Vector3, pos: Vector3, mat: Material, collide: bool = true, yaw_deg: float = 0.0) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = mat
	if collide:
		var body := StaticBody3D.new()
		body.name = n
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		body.position = pos
		body.rotation_degrees.y = yaw_deg
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		mi.name = "Mesh"
		body.add_child(mi)
		body.add_child(shape)
		parent.add_child(body)
		return body
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	parent.add_child(mi)
	return mi


func _cylinder(parent: Node, n: String, radius: float, height: float, pos: Vector3, mat: Material, collide: bool = true) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.15
	mesh.height = height
	mesh.radial_segments = 7
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if collide:
		var body := StaticBody3D.new()
		body.name = n
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		body.position = pos
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius * 1.05
		cyl.height = height
		shape.shape = cyl
		mi.name = "Mesh"
		body.add_child(mi)
		body.add_child(shape)
		parent.add_child(body)
		return body
	mi.name = n
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- 지면

func _build_ground() -> void:
	# 바깥 올리브 지면(카메라 경계 밖이 비어 보이지 않도록 넉넉히)
	var outer := _box(self, "GroundOuter", Vector3(80.0, 0.2, 80.0), Vector3(0.0, -0.1, 0.0), MAT_GRASS)
	outer.name = "GroundOuter"
	# 안뜰 흙바닥: 광장 중심에서 동쪽 통로/계단으로 이어지는 큰 흙 색면 2장
	_box(self, "GroundDust", Vector3(11.0, 0.06, 10.0), Vector3(1.0, 0.0, -1.0), MAT_GROUND, false)
	_box(self, "GroundDustE", Vector3(11.0, 0.06, 4.2), Vector3(11.5, 0.0, 0.0), MAT_GROUND, false)
	_box(self, "GroundDustN", Vector3(4.0, 0.06, 8.0), Vector3(13.0, 0.0, -4.0), MAT_GROUND, false)
	# 큼직한 풀 색면 (디테일 없이 큰 덩어리 2개)
	_box(self, "GrassPatchW", Vector3(9.0, 0.05, 11.0), Vector3(-12.5, 0.02, 4.0), MAT_OLIVE_LIGHT, false)
	_box(self, "GrassPatchS", Vector3(14.0, 0.05, 6.0), Vector3(3.0, 0.02, 10.5), MAT_OLIVE_LIGHT, false)


# ---------------------------------------------------------------- 중앙 광장 돌길

func _build_plaza() -> void:
	# 체커 타일 광장 8×8 (모래빛 / 청회, 일부 빠짐) — 레퍼런스의 체크무늬 바닥
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var tiles := Node3D.new()
	tiles.name = "CheckerFloor"
	add_child(tiles)
	for ix in 8:
		for iz in 8:
			if rng.randf() < 0.14:
				continue
			var mat := MAT_STONE_LIT if (ix + iz) % 2 == 0 else MAT_TILE_DARK
			_box(tiles, "Tile%d_%d" % [ix, iz], Vector3(0.96, 0.07, 0.96), Vector3(-3.5 + ix, 0.045, -3.5 + iz), mat, false)
	_box(self, "Flagstone2", Vector3(3.0, 0.08, 9.0), Vector3(7.0, 0.05, -1.0), MAT_STONE_LIT, false, 90.0)
	_box(self, "Flagstone3", Vector3(2.6, 0.08, 6.0), Vector3(0.0, 0.05, -7.5), MAT_STONE_LIT, false)


# ---------------------------------------------------------------- 돌담 (모듈 6개)

func _build_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	# 남쪽 긴 담 (Blender 블록 모듈)
	EnvAssets.wall(walls, "WallS1", 12.0, Vector3(-8.0, 0.0, 13.0))
	EnvAssets.wall(walls, "WallS2", 10.0, Vector3(8.0, 0.0, 13.0))
	# 서쪽 담 (틈 하나)
	EnvAssets.wall(walls, "WallW1", 9.0, Vector3(-17.0, 0.0, 8.0), 90.0)
	EnvAssets.wall(walls, "WallW2", 8.0, Vector3(-17.0, 0.0, -8.0), 90.0)
	# 동쪽 좁은 통로를 만드는 담 두 줄. 북벽은 x 7~11 까지만 — 계단(x 11.4~14.6) 앞은 비워 둔다
	EnvAssets.wall(walls, "CorridorN", 4.0, Vector3(9.0, 0.0, -2.1))
	EnvAssets.wall(walls, "CorridorS", 8.0, Vector3(11.0, 0.0, 2.1))
	# 북쪽 짧은 담 + 모서리 기둥
	EnvAssets.wall(walls, "WallN1", 9.0, Vector3(-6.5, 0.0, -13.0))
	EnvAssets.spawn(walls, "cap_pillar_a", Vector3(-1.6, 0.0, -13.0))


# ---------------------------------------------------------------- 계단 + 단차 (보이는 계단 ≠ 충돌 램프)

func _build_stairs_and_terrace() -> void:
	var terrace := Node3D.new()
	terrace.name = "Terrace"
	add_child(terrace)
	# 북동 단차: 1.0m 높이 테라스 (더미 공간)
	_box(terrace, "TerraceTop", Vector3(10.0, 1.0, 8.0), Vector3(13.0, 0.5, -9.0), MAT_STONE_LIT)
	EnvAssets.wall(terrace, "TerraceEdgeW", 8.0, Vector3(8.25, 0.0, -9.0), 90.0)
	# 계단: 5단 × (높이 0.2, 깊이 0.4) — 메시만, 충돌 없음
	var stairs := Node3D.new()
	stairs.name = "StairsVisual"
	terrace.add_child(stairs)
	var base := Vector3(13.0, 0.0, -5.0)   # 테라스 남쪽 면에서 남쪽(+Z)으로 내려옴
	for i in 5:
		var h := 0.2 * (i + 1)
		var z := base.z + 2.0 - 0.4 * (i + 0.5)
		_box(stairs, "Step%d" % i, Vector3(3.2, h, 0.4), Vector3(base.x, h * 0.5, z), MAT_STONE_LIT, false)
	# 충돌용 완만한 램프 (26.57°)
	var ramp := StaticBody3D.new()
	ramp.name = "StairsRamp"
	ramp.collision_layer = LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var run := 2.0
	var rise := 1.0
	box.size = Vector3(3.2, 0.2, sqrt(run * run + rise * rise))
	shape.shape = box
	ramp.add_child(shape)
	ramp.position = Vector3(base.x, rise * 0.5 - 0.1, base.z + run * 0.5)
	ramp.rotation.x = atan2(rise, run)
	terrace.add_child(ramp)
	# 계단 양옆 낮은 난간 (돌담 모듈, 계단 앞은 막지 않는다)
	EnvAssets.wall(terrace, "StairSideE", 2.4, Vector3(14.9, 0.0, -3.8), 90.0)
	EnvAssets.wall(terrace, "StairSideW", 2.4, Vector3(11.1, 0.0, -3.8), 90.0)


# ---------------------------------------------------------------- 폐허 건물 (입구 1, 지붕 분리)

func _build_ruin_building() -> void:
	var b := Node3D.new()
	b.name = "RuinHouse"
	add_child(b)
	var cx := -10.0
	var cz := -7.5
	var w := 7.0
	var d := 6.0
	var h := EnvAssets.WALL_TALL_H
	# 벽 4면(Blender 블록 모듈), 남쪽 벽에 입구(폭 1.6)
	EnvAssets.wall(b, "WallN", w, Vector3(cx, 0.0, cz - d * 0.5), 0.0, true)
	EnvAssets.wall(b, "WallW", d, Vector3(cx - w * 0.5, 0.0, cz), 90.0, true)
	EnvAssets.wall(b, "WallE", d, Vector3(cx + w * 0.5, 0.0, cz), 90.0, false)  # 무너진 낮은 벽
	var door_w := 1.6
	var seg := (w - door_w) * 0.5
	EnvAssets.wall(b, "WallS_L", seg, Vector3(cx - w * 0.5 + seg * 0.5, 0.0, cz + d * 0.5), 0.0, true)
	EnvAssets.wall(b, "WallS_R", seg, Vector3(cx + w * 0.5 - seg * 0.5, 0.0, cz + d * 0.5), 0.0, true)
	_box(b, "Lintel", Vector3(door_w + 0.2, 0.6, 0.5), Vector3(cx, h - 0.3, cz + d * 0.5), MAT_STONE_LIT)
	# 바닥
	_box(b, "Floor", Vector3(w, 0.1, d), Vector3(cx, 0.05, cz), MAT_SLATE, false)
	# 지붕 — 별도 노드. 플레이어가 안에 들어가면 숨긴다 (GDD §8 가림 처리 1차 추천)
	roof = Node3D.new()
	roof.name = "Roof"
	b.add_child(roof)
	# 붉은 박공 지붕: 용마루가 x 축, 양쪽 경사면 28°
	var pitch := deg_to_rad(28.0)
	var half_d := (d + 1.0) * 0.5
	var slope_len := half_d / cos(pitch)
	for side in [-1.0, 1.0]:
		var slab := _box(roof, "RoofSlab%s" % ("N" if side < 0 else "S"), Vector3(w + 1.0, 0.22, slope_len), Vector3(cx, h + slope_len * sin(pitch) * 0.5, cz + side * half_d * 0.5), MAT_ROOF, false)
		slab.rotation.x = -side * pitch
	_box(roof, "Ridge", Vector3(w + 1.1, 0.18, 0.3), Vector3(cx, h + slope_len * sin(pitch) + 0.02, cz), MAT_ROOF, false)
	# 박공 벽 (지붕 아래 삼각 벽 대신 낮은 벽 두 장)
	_box(roof, "GableW", Vector3(0.3, 0.9, d * 0.6), Vector3(cx - w * 0.5, h + 0.45, cz), MAT_STONE, false)
	# 지붕 트리거
	var area := Area3D.new()
	area.name = "RoofTrigger"
	area.collision_layer = 0
	area.collision_mask = 2  # Player
	area.position = Vector3(cx, h * 0.5, cz)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w - 0.6, h, d - 0.6)
	cs.shape = bs
	area.add_child(cs)
	area.body_entered.connect(func(_body): roof.visible = false)
	area.body_exited.connect(func(_body): roof.visible = true)
	b.add_child(area)


# ---------------------------------------------------------------- 나무 (Blender 에셋, 카드가 카메라를 향해 구워져 있어 yaw 0 고정)

func _build_trees() -> void:
	var trees := Node3D.new()
	trees.name = "Trees"
	add_child(trees)
	# 자작나무 (흰 줄기, 작은 잎 뭉치) + 고사목 (레퍼런스)
	EnvAssets.spawn(trees, "birch_a", Vector3(-13.5, 0.0, 6.0))
	EnvAssets.spawn(trees, "birch_b", Vector3(4.5, 0.0, -11.0))
	EnvAssets.spawn(trees, "birch_c", Vector3(15.5, 1.0, -12.5), 0.0, 0.85)
	EnvAssets.spawn(trees, "birch_a", Vector3(-15.0, 0.0, -4.5), 0.0, 0.9)
	EnvAssets.spawn(trees, "birch_b", Vector3(9.5, 0.0, 7.5))
	EnvAssets.spawn(trees, "dead_tree_a", Vector3(-7.0, 0.0, 11.8))
	EnvAssets.spawn(trees, "dead_tree_b", Vector3(16.8, 0.0, -1.0), 0.0, 0.9)


# ---------------------------------------------------------------- 그림자 가림 시험 구조물

func _build_shadow_pillar() -> void:
	# 광장 남동쪽 높은 아치 기둥 2개 + 상단 보: 플레이어가 그 그림자 속을 걸으며 밴드 변화를 본다
	_box(self, "ArchPostA", Vector3(0.8, 4.5, 0.8), Vector3(3.0, 2.25, 6.0), MAT_STONE)
	_box(self, "ArchPostB", Vector3(0.8, 4.5, 0.8), Vector3(7.0, 2.25, 6.0), MAT_STONE)
	_box(self, "ArchBeam", Vector3(5.2, 0.7, 1.0), Vector3(5.0, 4.6, 6.0), MAT_STONE_LIT, false)


# ---------------------------------------------------------------- 디테일 (큰 덩어리만, 소품 금지 원칙 유지)

## 돌담 갓돌, 무너진 돌덩이, 광장 중앙 부서진 기둥, 집 창 구멍/문설주, 나뭇가지.
## 저해상도 픽셀 에지가 면을 분리해 주므로 덩어리 수는 적게, 높이 차는 또렷하게.
func _build_details() -> void:
	var d := Node3D.new()
	d.name = "Details"
	add_child(d)
	# 무너져 떨어진 돌 블록 (Blender, 깎인 육면체)
	EnvAssets.spawn(d, "block_a", Vector3(-3.0, 0.0, 11.6), 25.0)
	EnvAssets.spawn(d, "block_b", Vector3(-1.6, 0.0, 11.2), -40.0, 0.8)
	EnvAssets.spawn(d, "block_a", Vector3(5.6, 0.0, -3.6), 60.0, 0.9)
	EnvAssets.spawn(d, "block_b", Vector3(-14.5, 0.0, -5.5), 15.0)
	# 바위 (풀밭 가장자리와 통로 주변)
	EnvAssets.spawn(d, "rock_a", Vector3(-15.5, 0.0, 2.0), 20.0, 1.1)
	EnvAssets.spawn(d, "rock_b", Vector3(-9.5, 0.0, 9.5), 110.0, 0.9)
	EnvAssets.spawn(d, "rock_c", Vector3(-11.5, 0.0, -1.5), -30.0, 0.8)
	EnvAssets.spawn(d, "rock_a", Vector3(3.0, 0.0, -9.0), 80.0, 0.9)
	EnvAssets.spawn(d, "rock_b", Vector3(16.5, 0.0, 4.5), 200.0, 1.2)
	EnvAssets.spawn(d, "rock_d", Vector3(-6.0, 0.0, 11.5), 45.0, 1.0)
	EnvAssets.spawn(d, "rock_d", Vector3(6.5, 0.0, 10.8), -70.0, 1.3)
	EnvAssets.spawn(d, "rock_c", Vector3(15.5, 1.0, -11.5), 140.0, 0.7)
	EnvAssets.spawn(d, "rock_d", Vector3(-12.5, 0.0, 3.5), 10.0, 0.7)
	# 덤불 둔덕 (풀밭 경계를 둥글게)
	for b in [["bush2_b", Vector3(-16.0, 0.0, 10.5)], ["bush2_a", Vector3(-9.0, 0.0, 2.5)], ["bush2_c", Vector3(-3.5, 0.0, 12.0)],
			["bush2_b", Vector3(10.5, 0.0, 10.5)], ["bush2_a", Vector3(0.0, 0.0, -12.0)], ["bush2_b", Vector3(17.0, 0.0, 8.0)],
			["bush2_a", Vector3(-15.0, 0.0, -9.5)], ["bush2_c", Vector3(-9.5, 0.0, 12.5)], ["bush2_c", Vector3(-12.0, 0.0, -1.0)],
			["bush2_a", Vector3(-16.5, 0.0, 3.0)], ["bush2_c", Vector3(3.5, 0.0, 12.0)], ["bush2_b", Vector3(-5.5, 0.0, -11.5)]]:
		EnvAssets.spawn(d, b[0], b[1])
	# 폐허 기둥
	EnvAssets.spawn(d, "pillar_a", Vector3(6.0, 0.0, 11.0), 15.0)
	EnvAssets.spawn(d, "pillar_a", Vector3(-6.0, 0.0, -2.5), 40.0, 0.8)
	# 피라미드 캡 돌기둥 (레퍼런스 담장 기둥): 통로 입구, 테라스 모서리, 남쪽 담 끝
	EnvAssets.spawn(d, "cap_pillar_a", Vector3(7.0, 0.0, -2.1))
	EnvAssets.spawn(d, "cap_pillar_a", Vector3(7.0, 0.0, 2.1))
	EnvAssets.spawn(d, "cap_pillar_b", Vector3(17.6, 1.0, -5.2))
	EnvAssets.spawn(d, "cap_pillar_b", Vector3(8.3, 1.0, -13.0))
	EnvAssets.spawn(d, "cap_pillar_a", Vector3(13.2, 0.0, 13.0))
	EnvAssets.spawn(d, "cap_pillar_b", Vector3(-17.0, 0.0, 3.2))
	# 광장 중앙 부서진 기둥 (받침 + 짧은 기둥)
	_box(d, "PlinthBase", Vector3(1.6, 0.3, 1.6), Vector3(0.0, 0.2, -3.0), MAT_STONE_LIT)
	_cylinder(d, "BrokenColumn", 0.42, 1.5, Vector3(0.0, 1.1, -3.0), MAT_STONE)
	# 집: 서쪽 벽 창 구멍은 벽을 뚫는 대신 어두운 판 + 창턱으로 표현, 남쪽 입구 문설주 2개
	_box(d, "DoorPostL", Vector3(0.35, 2.7, 0.7), Vector3(-10.95, 1.35, -4.5), MAT_STONE_LIT)
	_box(d, "DoorPostR", Vector3(0.35, 2.7, 0.7), Vector3(-9.05, 1.35, -4.5), MAT_STONE_LIT)
	# 테라스 가장자리 난간 조각 2개
	EnvAssets.wall(d, "ParapetA", 3.0, Vector3(10.5, 1.0, -12.75))
	EnvAssets.wall(d, "ParapetB", 2.2, Vector3(16.2, 1.0, -12.75))


# ---------------------------------------------------------------- 맵 경계 (보이지 않는 충돌)

## 36×28 플레이 영역 바깥으로 나가지 못하게 하는 투명 벽. 카메라 클램프와 함께 빈 공간 노출을 막는다.
func _build_boundary() -> void:
	var b := Node3D.new()
	b.name = "Boundary"
	add_child(b)
	var hw := 18.0
	var hd := 14.0
	var h := 3.0
	_invisible_wall(b, "N", Vector3(hw * 2.0 + 1.0, h, 0.5), Vector3(0.0, h * 0.5, -hd - 0.25))
	_invisible_wall(b, "S", Vector3(hw * 2.0 + 1.0, h, 0.5), Vector3(0.0, h * 0.5, hd + 0.25))
	_invisible_wall(b, "W", Vector3(0.5, h, hd * 2.0 + 1.0), Vector3(-hw - 0.25, h * 0.5, 0.0))
	_invisible_wall(b, "E", Vector3(0.5, h, hd * 2.0 + 1.0), Vector3(hw + 0.25, h * 0.5, 0.0))


func _invisible_wall(parent: Node, n: String, size: Vector3, pos: Vector3) -> void:
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
