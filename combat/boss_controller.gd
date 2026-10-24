## 시험용 보스 (GDD §8, §9, §11). 패턴 선행 모션(절차 포즈), 바닥 위험 영역, 유효 타격 판정, 경직/그로기.
## 패턴 FSM: SELECT(IDLE/APPROACH) → WINDUP → [ACTIVE(→GAP→ACTIVE2) | FATAL(FatalReactionController)] → RECOVERY → IDLE
## 모든 타격 판정 결과는 BossHitResolver 로 보낸다. 보스 자신은 플레이어를 죽이지 않는다.
class_name BossController
extends CharacterBody3D

signal pattern_started(p: BossAttackPattern)
signal pattern_finished(p: BossAttackPattern)
signal pattern_skipped(p: BossAttackPattern, reason: String)
signal hp_changed(hp: int, max_hp: int)
signal died

enum State { IDLE, APPROACH, WINDUP, ACTIVE, GAP, ACTIVE2, FATAL, RECOVERY, STAGGER, GROGGY, DEAD }

const MAT_BODY := preload("res://materials/mat_boss.tres")
const MAT_BLADE := preload("res://materials/mat_buckle.tres")
const MAT_EYE := preload("res://materials/mat_stone_lit.tres")

@export var max_hp: int = 12
@export var approach_speed: float = 2.8
## 패턴을 시작하는 거리 (m)
@export var engage_distance: float = 2.8
@export var hit_radius: float = 0.9
@export var turn_speed: float = 14.0
@export var stagger_seconds: float = 0.60
@export var groggy_seconds: float = 1.2
@export var parries_for_groggy: int = 3

var hp: int = 12
var state: State = State.IDLE
var pattern: BossAttackPattern
var pending: BossAttackPattern
var player: PlayerController
var camera_rig: CameraFollow
var resolver: BossHitResolver
var fatal: FatalReactionController
var parry_count: int = 0
var facing: Vector3 = Vector3(0, 0, 1)

var _t: float = 0.0
var _zone: DangerZone
var _zone2: DangerZone
var _hit_done: bool = false
var _fatal_success: bool = false
var _move_left: float = 0.0      # 돌진 중 남은 거리
var _move_dir: Vector3 = Vector3.ZERO
var _move_speed: float = 0.0
var _home: Transform3D
var _flinch: float = 0.0
var _recovery_len: float = 0.3

# ---- 절차 포즈
var _visual: Node3D
var _torso: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _glint: MeshInstance3D
var _pose := {"armR": Vector3(0, 0, 0), "armL": Vector3(0, 0, 0), "lean": 0.0, "lift": 0.0, "crouch": 0.0}
var _pose_target := {}
var _pose_rate: float = 10.0

## 자세: armR/armL = (pitch, yaw, roll) 도, lean = 상체 앞(+)/뒤(−) 도, lift = 몸 상승(m), crouch = 몸 하강(m)
const POSE_REST := {"armR": Vector3(8, 0, -6), "armL": Vector3(8, 0, 6), "lean": 2.0, "lift": 0.0, "crouch": 0.0}


func _ready() -> void:
	hp = max_hp
	_home = global_transform
	_build_visual()
	_pose_target = POSE_REST.duplicate()
	add_to_group("attack_targets")
	add_to_group("boss")


# ---------------------------------------------------------------- 외형 (프리미티브, 외곽선 없음)

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_torso = Node3D.new()
	_torso.name = "Torso"
	_torso.position = Vector3(0, 1.25, 0)
	_visual.add_child(_torso)
	_box(_torso, "Chest", Vector3(1.35, 1.45, 0.85), Vector3(0, 0.75, 0), MAT_BODY)
	_box(_torso, "Head", Vector3(0.55, 0.5, 0.55), Vector3(0, 1.75, -0.05), MAT_BODY)
	_box(_torso, "Eye", Vector3(0.36, 0.06, 0.08), Vector3(0, 1.78, -0.32), MAT_EYE)
	_box(_torso, "Hood", Vector3(0.75, 0.3, 0.75), Vector3(0, 1.95, 0.0), MAT_BODY)
	_box(_visual, "LegL", Vector3(0.42, 1.3, 0.42), Vector3(-0.38, 0.65, 0), MAT_BODY)
	_box(_visual, "LegR", Vector3(0.42, 1.3, 0.42), Vector3(0.38, 0.65, 0), MAT_BODY)
	_arm_r = Node3D.new()
	_arm_r.name = "ArmR"
	_arm_r.position = Vector3(0.85, 1.35, 0)
	_torso.add_child(_arm_r)
	_box(_arm_r, "UpperR", Vector3(0.36, 1.2, 0.36), Vector3(0, -0.6, 0), MAT_BODY)
	_box(_arm_r, "Blade", Vector3(0.14, 2.6, 0.09), Vector3(0, -2.3, 0), MAT_BLADE)
	_arm_l = Node3D.new()
	_arm_l.name = "ArmL"
	_arm_l.position = Vector3(-0.85, 1.35, 0)
	_torso.add_child(_arm_l)
	_box(_arm_l, "UpperL", Vector3(0.36, 1.2, 0.36), Vector3(0, -0.6, 0), MAT_BODY)
	# 은색 반짝임: 밝은 구 + 십자 스파이크, 예고 중 맥동 (패링 가능 패턴에만)
	var g := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	sm.radial_segments = 10
	sm.rings = 5
	g.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.97, 0.98, 1.0)
	g.material_override = gm
	g.position = Vector3(0, -3.55, 0)
	g.visible = false
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arm_r.add_child(g)
	for axis in [Vector3(1.6, 0.07, 0.07), Vector3(0.07, 1.6, 0.07), Vector3(0.07, 0.07, 1.6)]:
		var spike := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = axis
		spike.mesh = bm
		spike.material_override = gm
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(spike)
	_glint = g


func _box(parent: Node, n: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- 외부 API

## 디렉터가 보스가 IDLE 일 때 한 번 호출. 멀면 접근 후 시작.
func request_pattern(p: BossAttackPattern) -> void:
	if state != State.IDLE:
		return
	pending = p
	state = State.APPROACH


func stop_all() -> void:
	state = State.IDLE
	pending = null
	pattern = null
	velocity = Vector3.ZERO
	_clear_zones()
	_glint.visible = false
	_pose_target = POSE_REST.duplicate()


func reset_boss() -> void:
	stop_all()
	hp = max_hp
	parry_count = 0
	global_transform = _home
	facing = -_home.basis.z
	_pose = POSE_REST.duplicate()
	_apply_pose()
	hp_changed.emit(hp, max_hp)


func distance_to_player() -> float:
	var d := player.global_position - global_position
	d.y = 0.0
	return d.length()


## 플레이어 공격/탄 → 피해. 소폭 경직(시각 움찔)만, 패턴은 중단하지 않는다.
func receive_hit(_from_dir: Vector3, damage: int = 1) -> void:
	if state == State.DEAD:
		return
	hp = maxi(0, hp - damage)
	_flinch = 0.08
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		state = State.DEAD
		velocity = Vector3.ZERO
		_clear_zones()
		_glint.visible = false
		_pose_target = {"armR": Vector3(30, 0, -40), "armL": Vector3(30, 0, 40), "lean": 35.0, "lift": 0.0, "crouch": 0.9}
		died.emit()


# ---------------------------------------------------------------- 패턴 흐름

func _physics_process(delta: float) -> void:
	if player == null:
		return
	_t += delta
	match state:
		State.IDLE:
			_face_player(delta)
			velocity = Vector3.ZERO
		State.APPROACH:
			_face_player(delta)
			if distance_to_player() > engage_distance:
				velocity = facing * approach_speed
				move_and_slide()
			else:
				velocity = Vector3.ZERO
				_try_start(pending)
		State.WINDUP:
			if _t >= pattern.telegraph_game_seconds:
				if pattern.is_fatal():
					state = State.FATAL
					_t = 0.0
					fatal.begin(pattern, self)
				else:
					_begin_active()
			elif pattern.visual_cue == "silver_glint" and _t >= pattern.telegraph_game_seconds * 0.35:
				_glint.visible = true
				var k := (_t / pattern.telegraph_game_seconds - 0.35) / 0.65
				_glint.scale = Vector3.ONE * (0.8 + 0.9 * absf(sin(k * PI * 3.0)))
				_glint.rotation.y += delta * 9.0
		State.ACTIVE, State.ACTIVE2:
			_step_move(delta)
			if not _hit_done and not pattern.is_fatal():
				var z := _zone2 if state == State.ACTIVE2 else _zone
				if z and z.contains_point(player.global_position):
					if resolver.boss_hit_player(pattern, self, "active" if state == State.ACTIVE else "active2"):
						_hit_done = true
			if pattern == null:
				return   # 피격 처리 중 stop_all() 로 패턴이 끝났다
			if _t >= pattern.active_game_seconds:
				if state == State.ACTIVE and pattern.visual_cue == "double_sweep":
					state = State.GAP
					_t = 0.0
					_zone.set_intensity(0.12)
					_pose_target["armR"] = Vector3(-80, 80, 0)
				else:
					_begin_recovery(_recovery_len)
		State.GAP:
			if _t >= 0.22:
				state = State.ACTIVE2
				_t = 0.0
				_hit_done = false
				_zone2.set_intensity(0.5, true)
				_pose_target["armR"] = Vector3(-80, -90, 0)
		State.FATAL:
			pass   # FatalReactionController 가 fatal_strike / fatal_parried 로 돌려준다
		State.RECOVERY, State.STAGGER, State.GROGGY:
			if _t >= _recovery_len:
				_finish()
		State.DEAD:
			velocity = Vector3.ZERO


func _try_start(p: BossAttackPattern) -> void:
	pending = null
	if p == null:
		state = State.IDLE
		return
	# 안전 방향 도착점 검증 (GDD §5): 막혀 있으면 이 패턴은 고르지 않는다
	if p.is_fatal() and p.requires_clear_destination:
		for d in p.screen_safe_directions:
			var dir := fatal.screen_dir_world(d)
			var why := destination_blocked_reason(player.global_position, dir, p.reaction_step_meters)
			if why != "":
				state = State.IDLE
				pattern_skipped.emit(p, "%s destination blocked: %s" % [d, why])
				return
	_start_pattern(p)


func _start_pattern(p: BossAttackPattern) -> void:
	pattern = p
	_t = 0.0
	_hit_done = false
	_fatal_success = false
	_recovery_len = p.recovery_game_seconds
	_snap_face_player()
	_build_zones(p)
	_pose_target = _windup_pose(p)
	_pose_rate = 9.0
	state = State.WINDUP
	pattern_started.emit(p)


func _begin_active() -> void:
	state = State.ACTIVE
	_t = 0.0
	_hit_done = false
	_glint.visible = false
	_zone.set_intensity(0.5, true)
	_pose_target = _strike_pose(pattern)
	_pose_rate = 40.0
	match pattern.visual_cue:
		"straight_lunge":
			_move_dir = facing
			_move_left = 3.5
			_move_speed = 3.5 / maxf(pattern.active_game_seconds, 0.01)
		"right_thrust":
			_move_dir = fatal.screen_dir_world("RIGHT")
			_move_left = 2.0
			_move_speed = 2.0 / maxf(pattern.active_game_seconds, 0.01)
		_:
			_move_left = 0.0


func _step_move(delta: float) -> void:
	if _move_left <= 0.0:
		velocity = Vector3.ZERO
		return
	var step := minf(_move_left, _move_speed * delta)
	velocity = _move_dir * (step / maxf(delta, 0.0001))
	move_and_slide()
	_move_left -= step


func _begin_recovery(length: float, st: State = State.RECOVERY) -> void:
	state = st
	_t = 0.0
	_recovery_len = length
	_clear_zones()
	_glint.visible = false
	_move_left = 0.0
	velocity = Vector3.ZERO
	match st:
		State.STAGGER:
			_pose_target = {"armR": Vector3(-30, 40, 0), "armL": Vector3(-20, -20, 10), "lean": -18.0, "lift": 0.0, "crouch": 0.0}
		State.GROGGY:
			_pose_target = {"armR": Vector3(20, 0, -30), "armL": Vector3(20, 0, 30), "lean": 30.0, "lift": 0.0, "crouch": 0.5}
		_:
			_pose_target = {"armR": Vector3(-20, 20, 0), "armL": Vector3(10, 0, 6), "lean": 8.0, "lift": 0.0, "crouch": 0.1}
	_pose_rate = 8.0


func _finish() -> void:
	var p := pattern
	pattern = null
	state = State.IDLE
	_pose_target = POSE_REST.duplicate()
	_pose_rate = 6.0
	pattern_finished.emit(p)


## FatalReactionController: 판단 창 열림 → 영역 신호
func on_decision_opened() -> void:
	if _zone:
		_zone.set_intensity(0.62, true)


## FatalReactionController: 결과 확정 후 보스가 실제 타격 모션을 낸다. success=true 면 플레이어가 무적.
func fatal_strike(success: bool) -> void:
	if state != State.FATAL:
		return
	_fatal_success = success
	_begin_active()
	# 치명적 패턴의 ACTIVE 는 판정을 하지 않는다 (결과는 이미 확정). 성공 시 보스 후딜 = post_success
	_hit_done = true
	_recovery_len = pattern.post_success_boss_recovery_game_seconds if success else pattern.recovery_game_seconds


## FatalReactionController: 패링 성공 → 경직 / 3회 누적 시 그로기
func fatal_parried() -> void:
	if state != State.FATAL:
		return
	on_parried()


func on_parried() -> void:
	parry_count += 1
	_glint.visible = false
	if parry_count % parries_for_groggy == 0:
		_begin_recovery(groggy_seconds, State.GROGGY)
	else:
		var stagger_len := maxf(stagger_seconds, pattern.post_success_boss_recovery_game_seconds if pattern else 0.0)
		_begin_recovery(stagger_len, State.STAGGER)


func state_name() -> String:
	return State.keys()[state]


# ---------------------------------------------------------------- 영역 / 도착점 검증

func _build_zones(p: BossAttackPattern) -> void:
	_clear_zones()
	var origin := global_position
	match p.visual_cue:
		"horizontal_front_sweep":
			_zone = DangerZone.make("sector", {"radius": 3.2, "half_deg": 80.0}, origin, facing)
		"straight_lunge":
			_zone = DangerZone.make("corridor", {"length": 4.6, "half_width": 0.9}, origin, facing)
		"circular_ground_strike":
			_zone = DangerZone.make("circle", {"radius": 2.9}, origin, facing)
		"double_sweep":
			_zone = DangerZone.make("sector", {"radius": 3.2, "half_deg": 70.0, "offset_deg": -50.0}, origin, facing)
			_zone2 = DangerZone.make("sector", {"radius": 3.2, "half_deg": 70.0, "offset_deg": 50.0}, origin, facing)
			_zone2.set_intensity(0.12)
		_:
			# 치명적: 안전 방향 쐐기를 뺀 원판 (안전 방향이 없으면 정면 부채꼴 — 패링 전용)
			if p.screen_safe_directions.is_empty():
				_zone = DangerZone.make("sector", {"radius": 3.8, "half_deg": 70.0}, origin, facing)
			else:
				var angles := []
				for d in p.screen_safe_directions:
					angles.append(_world_dir_to_local_deg(fatal.screen_dir_world(d)))
				_zone = DangerZone.make("disc_minus_safe", {"radius": 4.6, "safe_angles_deg": angles, "safe_half_deg": 38.0}, origin, facing)
	if _zone:
		get_parent().add_child(_zone)
	if _zone2:
		get_parent().add_child(_zone2)


func _clear_zones() -> void:
	if _zone:
		_zone.queue_free()
		_zone = null
	if _zone2:
		_zone2.queue_free()
		_zone2 = null


## 월드 XZ 방향 → 보스 정면 기준 각도(도, + = 오른쪽)
func _world_dir_to_local_deg(dir: Vector3) -> float:
	var right := facing.cross(Vector3.UP).normalized()
	return rad_to_deg(atan2(dir.dot(right), dir.dot(facing)))


## 플레이어가 dir 로 meters 만큼 이동한 도착점이 비어 있는지. "" = 비어 있음, 아니면 이유
func destination_blocked_reason(from: Vector3, dir: Vector3, meters: float) -> String:
	if dir.length_squared() < 0.5:
		return "no direction"
	var dest := from + dir * meters
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.8, 0), dest + Vector3(0, 0.8, 0), 1)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		return "obstacle on path (%s)" % hit["collider"].name
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.45
	q.shape = sh
	q.transform = Transform3D(Basis(), dest + Vector3(0, 0.8, 0))
	q.collision_mask = 1
	var res := space.intersect_shape(q, 4)
	if not res.is_empty():
		return "obstacle at destination (%s)" % res[0]["collider"].name
	# 보스 몸통 위로 떨어지는 도착점도 막힌 것으로 본다
	var to_boss := dest - global_position
	to_boss.y = 0.0
	if to_boss.length() < hit_radius + 0.3:
		return "destination inside boss"
	return ""


# ---------------------------------------------------------------- 포즈

func _face_player(delta: float) -> void:
	var to := player.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return
	var goal := to.normalized()
	var yaw_now := atan2(-facing.x, -facing.z)
	var yaw_goal := atan2(-goal.x, -goal.z)
	var yaw := lerp_angle(yaw_now, yaw_goal, minf(1.0, turn_speed * delta))
	facing = Vector3(-sin(yaw), 0.0, -cos(yaw))


func _snap_face_player() -> void:
	var to := player.global_position - global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		facing = to.normalized()


## 예고 자세 — 동작 실루엣으로 공격 방향을 읽게 한다
func _windup_pose(p: BossAttackPattern) -> Dictionary:
	match p.visual_cue:
		"horizontal_front_sweep":
			return {"armR": Vector3(-80, 85, 0), "armL": Vector3(-20, -10, 10), "lean": -6.0, "lift": 0.0, "crouch": 0.0}
		"straight_lunge":
			return {"armR": Vector3(-95, 0, 0), "armL": Vector3(30, 0, 10), "lean": -14.0, "lift": 0.0, "crouch": 0.15}
		"circular_ground_strike":
			return {"armR": Vector3(-165, 0, -10), "armL": Vector3(-165, 0, 10), "lean": -10.0, "lift": 0.0, "crouch": 0.0}
		"double_sweep":
			return {"armR": Vector3(-80, -85, 0), "armL": Vector3(-30, 20, 10), "lean": -4.0, "lift": 0.0, "crouch": 0.0}
		"left_sweep":
			return {"armR": Vector3(-85, _arm_yaw_toward("RIGHT"), 0), "armL": Vector3(-20, 0, 10), "lean": -8.0, "lift": 0.0, "crouch": 0.0}
		"right_thrust":
			return {"armR": Vector3(35, _arm_yaw_toward("RIGHT") * 0.3, 0), "armL": Vector3(-40, 0, 10), "lean": -20.0, "lift": 0.0, "crouch": 0.2}
		"low_sweep":
			return {"armR": Vector3(-85, _arm_yaw_toward("LEFT"), 0), "armL": Vector3(-30, 0, 20), "lean": 12.0, "lift": 0.0, "crouch": 0.6}
		"silver_glint":
			if p.screen_safe_directions.is_empty():
				return {"armR": Vector3(-150, 0, 0), "armL": Vector3(-120, 0, 20), "lean": -12.0, "lift": 0.0, "crouch": 0.0}
			return {"armR": Vector3(-160, 0, 0), "armL": Vector3(-140, 0, 20), "lean": -8.0, "lift": 1.0, "crouch": 0.0}
	return POSE_REST.duplicate()


## 타격 자세
func _strike_pose(p: BossAttackPattern) -> Dictionary:
	match p.visual_cue:
		"horizontal_front_sweep":
			return {"armR": Vector3(-80, -90, 0), "armL": Vector3(10, 0, 10), "lean": 12.0, "lift": 0.0, "crouch": 0.1}
		"straight_lunge":
			return {"armR": Vector3(-95, 0, 0), "armL": Vector3(-40, 0, 10), "lean": 26.0, "lift": 0.0, "crouch": 0.25}
		"circular_ground_strike":
			return {"armR": Vector3(-20, 0, -30), "armL": Vector3(-20, 0, 30), "lean": 28.0, "lift": 0.0, "crouch": 0.45}
		"double_sweep":
			return {"armR": Vector3(-80, 80, 0), "armL": Vector3(10, 0, 10), "lean": 10.0, "lift": 0.0, "crouch": 0.1}
		"left_sweep":
			return {"armR": Vector3(-85, _arm_yaw_toward("LEFT"), 0), "armL": Vector3(10, 0, 10), "lean": 14.0, "lift": 0.0, "crouch": 0.1}
		"right_thrust":
			return {"armR": Vector3(-95, _arm_yaw_toward("RIGHT"), 0), "armL": Vector3(20, 0, 10), "lean": 28.0, "lift": 0.0, "crouch": 0.2}
		"low_sweep":
			return {"armR": Vector3(-85, _arm_yaw_toward("RIGHT"), 0), "armL": Vector3(10, 0, 20), "lean": 16.0, "lift": 0.0, "crouch": 0.7}
		"silver_glint":
			return {"armR": Vector3(-25, 0, 0), "armL": Vector3(-10, 0, 20), "lean": 30.0, "lift": 0.0, "crouch": 0.4}
	return POSE_REST.duplicate()


## 화면 방향으로 팔(검)을 향하게 하는 요(도). 보스 정면 기준.
func _arm_yaw_toward(dir_name: String) -> float:
	return -clampf(_world_dir_to_local_deg(fatal.screen_dir_world(dir_name)), -110.0, 110.0)


func _process(delta: float) -> void:
	var k := 1.0 - exp(-delta * _pose_rate)
	for key in _pose:
		var target = _pose_target.get(key, POSE_REST[key])
		_pose[key] = lerp(_pose[key], target, k)
	if _flinch > 0.0:
		_flinch -= delta
	_apply_pose()


func _apply_pose() -> void:
	var yaw := atan2(-facing.x, -facing.z)
	_visual.rotation.y = yaw
	var fl := 0.06 * sin(_flinch * 160.0) if _flinch > 0.0 else 0.0
	_visual.position = Vector3(fl, float(_pose["lift"]) - float(_pose["crouch"]), 0.0)
	_torso.rotation_degrees = Vector3(-float(_pose["lean"]), 0.0, 0.0)
	var ar: Vector3 = _pose["armR"]
	var al: Vector3 = _pose["armL"]
	# pitch: 음수 = 팔을 앞/위로 올림 (팔은 아래로 늘어진 상태가 0)
	_arm_r.rotation_degrees = Vector3(-ar.x, ar.y, ar.z)
	_arm_l.rotation_degrees = Vector3(-al.x, al.y, al.z)
