## 착지 먼지 구름: 작은 구 6~8개가 퍼지며 떠오르다 사라진다 (저채도, 외곽선 없음).
class_name DustPuff
extends Node3D

static func spawn(parent: Node, pos: Vector3, scale_k: float = 1.0) -> void:
	var puff := DustPuff.new()
	puff.name = "DustPuff"
	parent.add_child(puff)
	puff.global_position = pos
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec() % 100000)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.72, 0.68, 0.58, 0.55)
	var n := 7
	for i in n:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09 * scale_k
		sm.height = 0.18 * scale_k
		sm.radial_segments = 6
		sm.rings = 3
		mi.mesh = sm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := TAU * float(i) / float(n) + rng.randf_range(-0.3, 0.3)
		mi.position = Vector3(cos(ang) * 0.12, 0.06, sin(ang) * 0.12) * scale_k
		puff.add_child(mi)
		var out := Vector3(cos(ang) * 0.42, 0.22 + rng.randf() * 0.12, sin(ang) * 0.42) * scale_k
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "position", out, 0.32).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * 1.9, 0.32)
	var fade := puff.create_tween()
	fade.tween_property(mat, "albedo_color:a", 0.0, 0.34).set_delay(0.04)
	fade.tween_callback(puff.queue_free)
