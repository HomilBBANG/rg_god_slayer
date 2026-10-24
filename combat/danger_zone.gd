## 바닥 위험 영역 — 보스 패턴의 타격 폴리곤. 시각(흐릿한 저채도 붉은 색면) + 점 포함 판정을 한 곳에서.
## 로컬 좌표: 원점 = 보스 발, -Z = 보스 정면, +X = 보스 오른쪽.
class_name DangerZone
extends MeshInstance3D

## shape: "sector" {radius, half_deg, offset_deg} | "circle" {radius} | "corridor" {length, half_width}
##        | "disc_minus_safe" {radius, safe_angles_deg: Array, safe_half_deg}
var shape: String = "sector"
var params: Dictionary = {}
var _mat: StandardMaterial3D


static func make(shape_name: String, p: Dictionary, origin: Vector3, forward: Vector3) -> DangerZone:
	var z := DangerZone.new()
	z.name = "DangerZone"
	z.shape = shape_name
	z.params = p
	var f := Vector3(forward.x, 0.0, forward.z).normalized()
	var right := f.cross(Vector3.UP).normalized()
	z.transform = Transform3D(Basis(right, Vector3.UP, -f), origin + Vector3(0, 0.10, 0))   # 체커 타일(윗면 0.08) 위
	z.mesh = z._build_mesh()
	z._mat = StandardMaterial3D.new()
	z._mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	z._mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	z._mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	z._mat.no_depth_test = false
	z._mat.albedo_color = Color(0.60, 0.26, 0.22, 0.42)
	z._mat.render_priority = 2
	z.material_override = z._mat
	z.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return z


## 판단 창이 열리는 순간의 짧은 신호 / 유효 타격 중 강조
func set_intensity(a: float, bright: bool = false) -> void:
	if _mat:
		_mat.albedo_color = Color(0.78, 0.40, 0.30, a) if bright else Color(0.60, 0.26, 0.22, a)


## 월드 점이 영역 안인가 (XZ 만)
func contains_point(world: Vector3) -> bool:
	var local := global_transform.affine_inverse() * world
	var fwd := -local.z
	var side := local.x
	var dist := Vector2(side, fwd).length()
	var ang := rad_to_deg(atan2(side, fwd))   # 0 = 정면, + = 오른쪽
	match shape:
		"sector":
			return dist <= float(params["radius"]) and absf(wrapf(ang - float(params.get("offset_deg", 0.0)), -180.0, 180.0)) <= float(params["half_deg"])
		"circle":
			return dist <= float(params["radius"])
		"corridor":
			return fwd >= -0.3 and fwd <= float(params["length"]) and absf(side) <= float(params["half_width"])
		"disc_minus_safe":
			if dist > float(params["radius"]):
				return false
			return not _in_safe(ang)
	return false


func _in_safe(ang_deg: float) -> bool:
	for sa in params.get("safe_angles_deg", []):
		if absf(wrapf(ang_deg - float(sa), -180.0, 180.0)) <= float(params.get("safe_half_deg", 40.0)):
			return true
	return false


func _build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	match shape:
		"sector":
			_fan(verts, float(params["radius"]), float(params.get("offset_deg", 0.0)) - float(params["half_deg"]), float(params.get("offset_deg", 0.0)) + float(params["half_deg"]), Callable())
		"circle":
			_fan(verts, float(params["radius"]), -180.0, 180.0, Callable())
		"corridor":
			var L := float(params["length"])
			var w := float(params["half_width"])
			verts.append_array([Vector3(-w, 0, 0.3), Vector3(w, 0, 0.3), Vector3(w, 0, -L), Vector3(-w, 0, 0.3), Vector3(w, 0, -L), Vector3(-w, 0, -L)])
		"disc_minus_safe":
			_fan(verts, float(params["radius"]), -180.0, 180.0, Callable(self, "_in_safe"))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	if verts.size() >= 3:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _fan(verts: PackedVector3Array, r: float, a0: float, a1: float, skip: Callable) -> void:
	var step := 5.0
	var a := a0
	while a < a1 - 0.001:
		var b := minf(a + step, a1)
		var mid := (a + b) * 0.5
		if skip.is_valid() and skip.call(mid):
			a = b
			continue
		var pa := Vector3(sin(deg_to_rad(a)) * r, 0, -cos(deg_to_rad(a)) * r)
		var pb := Vector3(sin(deg_to_rad(b)) * r, 0, -cos(deg_to_rad(b)) * r)
		verts.append_array([Vector3.ZERO, pb, pa])
		a = b
