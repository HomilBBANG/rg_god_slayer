## 투사체: 직선 탄환(권총/라이플/단검) 또는 포물선 폭탄.
## 빠른 탄의 터널링을 막기 위해 매 물리 틱 이전 위치→현재 위치 구간을 레이캐스트로 검사한다.
class_name Projectile
extends Node3D

const MAT_BULLET := preload("res://materials/mat_buckle.tres")
const MAT_DAGGER := preload("res://materials/mat_stone_lit.tres")
const MAT_BOMB := preload("res://materials/mat_slate.tres")
const MAT_FLASH := preload("res://materials/mat_hair.tres")
const HIT_MASK := 1 | 4   # World + HitDummy

var velocity: Vector3 = Vector3.ZERO
var damage: int = 1
var max_range: float = 10.0
var lob: bool = false
var fuse: float = 0.0
var blast_radius: float = 0.0
var fall_gravity: float = 14.0
var hit_radius: float = 0.08
var _travelled: float = 0.0
var _done: bool = false


static func make(kind: String, from: Vector3, dir: Vector3, d: Dictionary) -> Projectile:
	var p := Projectile.new()
	p.name = "Projectile_" + kind
	p.damage = int(d.get("damage", 1))
	p.max_range = float(d.get("range", 10.0))
	var mi := MeshInstance3D.new()
	match kind:
		"bomb":
			p.lob = true
			p.fuse = float(d.get("fuse", 1.2))
			p.blast_radius = float(d.get("radius", 2.5))
			p.max_range = 100.0
			p.hit_radius = 0.16
			var m := SphereMesh.new()
			m.radius = 0.16
			m.height = 0.32
			m.radial_segments = 8
			m.rings = 4
			mi.mesh = m
			mi.material_override = MAT_BOMB
			# 앞으로 + 위로 던짐
			p.velocity = dir * float(d.get("speed", 7.0)) + Vector3.UP * 4.5
		"dagger":
			p.hit_radius = 0.12
			var m := BoxMesh.new()
			m.size = Vector3(0.05, 0.05, 0.38)
			mi.mesh = m
			mi.material_override = MAT_DAGGER
			p.velocity = dir * float(d.get("speed", 20.0))
		_:
			var m := BoxMesh.new()
			m.size = Vector3(0.05, 0.05, 0.28)
			mi.mesh = m
			mi.material_override = MAT_BULLET
			p.velocity = dir * float(d.get("speed", 30.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	p.position = from
	if dir.length_squared() > 0.0:
		p.look_at_from_position(from, from + dir, Vector3.UP)
	return p


func _physics_process(delta: float) -> void:
	if _done:
		return
	if lob:
		velocity.y -= fall_gravity * delta
		fuse -= delta
		if fuse <= 0.0:
			_explode()
			return
	var from := global_position
	var step := velocity * delta
	var to := from + step
	# 구간 레이캐스트 (시작점을 반지름만큼 뒤로 빼서 접촉 판정 보강)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from - step.normalized() * hit_radius, to + step.normalized() * hit_radius, HIT_MASK)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit["position"]
		_on_hit(hit["collider"])
		return
	global_position = to
	if lob and to.y <= hit_radius and velocity.y < 0.0:
		global_position.y = hit_radius
		_explode()
		return
	if lob:
		var up := Vector3.UP if velocity.length_squared() < 1e-6 else velocity.normalized()
		look_at(global_position + up, Vector3.UP if absf(up.y) < 0.99 else Vector3.FORWARD)
	_travelled += step.length()
	if not lob and _travelled >= max_range:
		_finish()


func _on_hit(body: Object) -> void:
	if _done:
		return
	if lob:
		# 폭탄은 지면/벽/더미에 닿으면 바로 터진다
		_explode()
		return
	if body is Node and body.has_method("receive_hit"):
		var to := (body as Node3D).global_position - global_position
		to.y = 0.0
		body.receive_hit(to.normalized(), damage)
	_finish()


func _explode() -> void:
	if _done:
		return
	_done = true
	for node in get_tree().get_nodes_in_group("attack_targets"):
		var t := node as Node3D
		if t == null:
			continue
		var to := t.global_position - global_position
		to.y = 0.0
		var r: float = blast_radius + float(t.get("hit_radius") if t.get("hit_radius") != null else 0.0)
		if to.length() <= r and t.has_method("receive_hit"):
			t.receive_hit(to.normalized(), damage)
	# 폭발 시각: 커졌다 사라지는 구
	var flash := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.3
	m.height = 0.6
	m.radial_segments = 12
	m.rings = 6
	flash.mesh = m
	flash.material_override = MAT_FLASH
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(flash)
	flash.global_position = global_position + Vector3(0, 0.3, 0)
	var tw := flash.create_tween()
	tw.tween_property(flash, "scale", Vector3.ONE * (blast_radius / 0.3), 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_callback(flash.queue_free)
	queue_free()


func _finish() -> void:
	_done = true
	queue_free()
