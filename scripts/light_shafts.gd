## 평면 셸 볼류메트릭 (기사 §Volumetric Lighting)
## 광원 방향 L 을 품은 평행 평면 N 장을 카메라를 향하도록 세워 겹친다.
## 평면 법선 n = (카메라 시선에서 L 성분을 뺀 것) → 평면은 L 과 평행하면서 최대한 카메라를 마주 본다.
## 각 평면은 RED_LightShaft 머티리얼로 그림자 밖인 곳만 빛을 가산한다. 태양 프리셋이 바뀌면 rebuild().
class_name LightShafts
extends Node3D

const SHADER := preload("res://shaders/RED_LightShaft.gdshader")

@export var plane_count: int = 12
@export var spacing: float = 1.6
## 평면 크기 (가로 = 맵 대각선 이상, 세로 = 빛 방향으로 덮을 길이)
@export var plane_size: Vector2 = Vector2(70.0, 18.0)
@export var center: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var enabled: bool = true

var _material: ShaderMaterial
var _planes: Array[MeshInstance3D] = []


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = -64
	var quad := QuadMesh.new()
	quad.size = plane_size
	quad.material = _material
	for i in plane_count:
		var mi := MeshInstance3D.new()
		mi.name = "Shaft%02d" % i
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 64.0
		add_child(mi)
		_planes.append(mi)
	visible = enabled


## light_dir: 빛이 진행하는 방향 (DirectionalLight3D 의 -basis.z), view_dir: 카메라가 보는 방향
func rebuild(light_dir: Vector3, view_dir: Vector3) -> void:
	var l := light_dir.normalized()
	# 시선에서 L 성분 제거 → 평면 법선. (시선 ∥ L 이면 아무 수직 벡터)
	var n := view_dir - l * view_dir.dot(l)
	if n.length_squared() < 0.0001:
		n = l.cross(Vector3.UP)
	n = n.normalized()
	var h := n.cross(l).normalized()      # 평면 안의 수평 축
	var up_in_plane := -l                 # 평면 안의 '위' 축 (빛의 반대 = 태양 쪽)
	var basis := Basis(h, up_in_plane, n)
	for i in _planes.size():
		var k := float(i) - float(_planes.size() - 1) * 0.5
		var pos := center + n * (k * spacing) + up_in_plane * (plane_size.y * 0.5 - 1.0)
		_planes[i].global_transform = Transform3D(basis, pos)
	print("[RED] light shafts: n=%s plane0=%s planeN=%s" % [n, _planes[0].global_position, _planes[-1].global_position])

