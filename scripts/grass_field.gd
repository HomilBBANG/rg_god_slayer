## 잔디 빌보드 필드 (기사 §Grass)
## 지정한 사각 영역들에 시드 기반 난수로 잔디 쿼드를 뿌린다. MultiMesh 1개 → 드로우콜 1회.
## 조명은 RED_Grass 가 LIGHT_VERTEX 로 밑동 기준 균일하게 처리한다.
class_name GrassField
extends MultiMeshInstance3D

const SHADER := preload("res://shaders/RED_Grass.gdshader")
const TUFT_TEX := preload("res://assets/environment/grass_tuft.png")

## [Rect2(x, z, w, d), density(개/m²)] 목록
@export var patches: Array = [
	[Rect2(-17.0, -1.5, 9.0, 11.0), 1.6],   # 서쪽 풀밭
	[Rect2(-4.0, 7.5, 14.0, 6.0), 1.6],     # 남쪽 풀밭
]
@export var seed_value: int = 7
@export var tuft_size: Vector2 = Vector2(0.55, 0.45)
@export var size_jitter: float = 0.35
@export var base_color: Color = Color(0.57, 0.61, 0.46)
## 플레이어 동선 (광장/돌길) 위에는 심지 않는다
@export var exclude_rects: Array = [Rect2(-3.6, -3.6, 7.2, 7.2)]


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var transforms: Array[Transform3D] = []
	for p in patches:
		var r: Rect2 = p[0]
		var count := int(r.size.x * r.size.y * float(p[1]))
		for i in count:
			var x := rng.randf_range(r.position.x, r.end.x)
			var z := rng.randf_range(r.position.y, r.end.y)
			if _excluded(x, z):
				continue
			var s := 1.0 + rng.randf_range(-size_jitter, size_jitter)
			var w := tuft_size.x * s
			var h := tuft_size.y * s
			# 쿼드 원점이 밑동이 되도록 h/2 올린다
			var t := Transform3D(Basis().scaled(Vector3(w, h, 1.0)), Vector3(x, h * 0.5 + 0.02, z))
			transforms.append(t)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	multimesh = mm

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("tuft_tex", TUFT_TEX)
	mat.set_shader_parameter("base_color", base_color)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _excluded(x: float, z: float) -> bool:
	for e in exclude_rects:
		if (e as Rect2).has_point(Vector2(x, z)):
			return true
	return false
