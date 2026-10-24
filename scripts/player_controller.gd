## 플레이어 (GDD §3~5 + 회피)
## - CharacterBody3D + move_and_slide, 물리 틱에서 이동
## - 카메라 화면 방향 기준 4방향/대각선 이동, 대각선 정규화. 가속/감속이 커서 즉답에 가깝다.
## - Z 단발 근접 공격 (0.30s: 준비 0.07 / 타격 0.07~0.16 / 복귀 ~0.30)
## - Shift 회피: 방향키 방향으로 짧은 점프. 입력이 없으면 보는 방향의 반대로 백스텝(시선은 정면 유지).
## - 애니메이션: 리깅된 모델(player_rigged.glb)의 Skeleton3D 뼈 포즈를 절차적으로 구동.
##   회전은 '모델 공간' 오일러로 쓰고 _pose() 가 뼈 로컬 공간으로 변환한다 (모델 정면 = -Z).
class_name PlayerController
extends CharacterBody3D

enum State { IDLE, WALK, ATTACK, DODGE }

@export_group("Movement")
@export var move_speed: float = 4.8
@export var acceleration: float = 40.0
@export var deceleration: float = 48.0
@export var gravity: float = 9.8
@export var turn_speed: float = 22.0

@export_group("Attack")
@export var attack_duration: float = 0.30
@export var attack_windup_end: float = 0.07
@export var attack_active_end: float = 0.16
@export var attack_range: float = 1.45
@export var attack_cone_deg: float = 100.0
@export var attack_move_factor: float = 0.6

@export_group("Dodge")
@export var dodge_duration: float = 0.26
@export var dodge_distance: float = 2.6
## 점프 초속 (m/s). 회피 중엔 dodge_gravity 를 써서 짧게 뜬다.
@export var dodge_hop: float = 2.2
@export var dodge_gravity: float = 18.0
@export var dodge_cooldown: float = 0.08

var state: State = State.IDLE
var facing: Vector3 = Vector3(0, 0, 1)
var move_input: Vector2 = Vector2.ZERO

var _attack_time: float = 0.0
var _attack_hit_done: Dictionary = {}
var _dodge_time: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
## 회피 방향이 시선 기준 앞(+1)/뒤(−1) 인지 — 애니메이션용
var _dodge_lean: float = 0.0
var _dodge_cd: float = 0.0
var _walk_phase: float = 0.0
var _idle_phase: float = 0.0

@onready var visual_root: Node3D = $VisualRoot
@onready var _model: Node3D = $VisualRoot/Model

var _camera_rig: CameraFollow
var _skel: Skeleton3D
## 뼈 인덱스
var _b: Dictionary = {}
var _rest_local: Dictionary = {}   # 뼈 로컬 rest 회전
var _rest_global: Dictionary = {}  # 모델 공간 rest 회전
var _hips_rest_pos: Vector3

## 논리 이름 → 실제 뼈 이름. 모델이 바뀌면 여기만 고친다 (현재: Mixamo 이름, 접두어 제거됨)
const BONE_MAP := {
	"Hips": "Hips", "Spine": "Spine", "Chest": "Spine2", "Neck": "Neck", "Head": "Head",
	"Shoulder.L": "LeftShoulder", "UpperArm.L": "LeftArm", "LowerArm.L": "LeftForeArm", "Hand.L": "LeftHand",
	"Shoulder.R": "RightShoulder", "UpperArm.R": "RightArm", "LowerArm.R": "RightForeArm", "Hand.R": "RightHand",
	"UpperLeg.L": "LeftUpLeg", "LowerLeg.L": "LeftLeg", "Foot.L": "LeftFoot",
	"UpperLeg.R": "RightUpLeg", "LowerLeg.R": "RightLeg", "Foot.R": "RightFoot",
}
## 머리카락 체인 (뿌리 → 끝). 각 체인은 스프링-댐퍼로 흔들린다.
const HAIR_CHAINS := [["HairBack1", "HairBack2", "HairBack3", "HairBack4"], ["HairL1", "HairL2"], ["HairR1", "HairR2"]]

@export_group("Hair")
## 흔들림 강도: 가속도(m/s²) → 뿌리 각도(도)
@export var hair_accel_gain: float = 4.5
## 회전 속도(rad/s) → 옆으로 쏠리는 각도(도)
@export var hair_turn_gain: float = 10.0
@export var hair_stiffness: float = 60.0
@export var hair_damping: float = 7.0
## 체인 뒤쪽 뼈가 앞 뼈를 따라가는 비율 (>1 이면 끝이 더 크게 휘어짐)
@export var hair_follow: float = 1.15
@export var hair_max_deg: float = 38.0
@export var hair_breeze_deg: float = 2.0

var _hair_angle: Dictionary = {}   # bone → Vector2(pitch, roll) 도
var _hair_vel: Dictionary = {}
var _prev_vel_local: Vector2 = Vector2.ZERO
var _prev_yaw: float = 0.0


func _ready() -> void:
	floor_snap_length = 0.3
	EnvAssets.apply_materials(_model)
	_camera_rig = get_tree().get_first_node_in_group("camera_rig") as CameraFollow
	_setup_skeleton()
	_apply_facing(0.0, true)


func _setup_skeleton() -> void:
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_error("[Player] Skeleton3D not found in model")
		return
	_skel = found[0] as Skeleton3D
	for n in BONE_MAP.keys():
		_register_bone(n, BONE_MAP[n])
	for chain in HAIR_CHAINS:
		for n in chain:
			if _register_bone(n, n):
				_hair_angle[n] = Vector2.ZERO
				_hair_vel[n] = Vector2.ZERO
	_hips_rest_pos = _skel.get_bone_rest(_b["Hips"]).origin
	_prev_yaw = visual_root.rotation.y
	# 모델 메시는 그림자를 드리운다
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _register_bone(logical: String, actual: String) -> bool:
	var i := _skel.find_bone(actual)
	if i < 0:
		push_warning("[Player] bone missing: %s (%s)" % [actual, logical])
		return false
	_b[logical] = i
	_rest_local[logical] = _skel.get_bone_rest(i).basis.get_rotation_quaternion()
	_rest_global[logical] = _skel.get_bone_global_rest(i).basis.get_rotation_quaternion()
	return true


## 모델 공간 오일러(도) 회전을 뼈에 적용. 부모 뼈의 움직임은 그대로 따라간다.
func _pose(n: String, euler_deg: Vector3) -> void:
	if not _b.has(n):
		return
	var r := Quaternion.from_euler(Vector3(deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)))
	var g: Quaternion = _rest_global[n]
	var local_delta := g.inverse() * r * g
	_skel.set_bone_pose_rotation(_b[n], (_rest_local[n] as Quaternion) * local_delta)


func _hips_offset(y: float) -> void:
	if _b.has("Hips"):
		_skel.set_bone_pose_position(_b["Hips"], _hips_rest_pos + Vector3(0.0, y, 0.0))


func _physics_process(delta: float) -> void:
	move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var wish_dir := _screen_to_world(move_input)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)

	# 회피: 회피 중이 아니면 언제든 (공격은 유효 타격이 끝난 뒤부터 캔슬 가능)
	if state != State.DODGE and _dodge_cd <= 0.0 and Input.is_action_just_pressed("dodge"):
		if state != State.ATTACK or _attack_time >= attack_active_end:
			_start_dodge(wish_dir)
	# 공격 시작: 복귀 완료 후에만 재입력 허용
	elif state != State.ATTACK and state != State.DODGE and Input.is_action_just_pressed("attack"):
		_start_attack()

	# 상태 갱신
	match state:
		State.ATTACK:
			_attack_time += delta
			if _attack_time >= attack_windup_end and _attack_time < attack_active_end:
				_do_attack_hitcheck()
			if _attack_time >= attack_duration:
				state = State.IDLE
		State.DODGE:
			_dodge_time += delta
			if _dodge_time >= dodge_duration and (is_on_floor() or _dodge_time > dodge_duration * 2.0):
				state = State.IDLE
				_dodge_cd = dodge_cooldown
	if state != State.ATTACK and state != State.DODGE:
		state = State.WALK if wish_dir.length_squared() > 0.0 else State.IDLE
		if state == State.WALK:
			facing = wish_dir

	# 수평 속도
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if state == State.DODGE:
		# 갈수록 느려지는 짧은 돌진: 평균 속도 = distance/duration
		var k := clampf(_dodge_time / dodge_duration, 0.0, 1.0)
		var speed := (dodge_distance / dodge_duration) * 2.0 * (1.0 - k)
		horizontal = _dodge_dir * speed
	else:
		var speed_cap := move_speed * (attack_move_factor if state == State.ATTACK else 1.0)
		var target_vel := wish_dir * speed_cap
		var rate := acceleration if wish_dir.length_squared() > 0.0 else deceleration
		horizontal = horizontal.move_toward(target_vel, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# 중력
	if is_on_floor() and state != State.DODGE:
		velocity.y = 0.0
	else:
		velocity.y -= (dodge_gravity if state == State.DODGE else gravity) * delta

	move_and_slide()

	_apply_facing(delta, false)
	if _skel:
		_animate(delta, horizontal.length() / move_speed)
		_animate_hair(delta, horizontal)


## 입력 벡터(화면 기준) → 월드 XZ 방향. ↑ = 화면 위 = 카메라 전방 투영.
func _screen_to_world(v: Vector2) -> Vector3:
	if v.length_squared() == 0.0:
		return Vector3.ZERO
	var right := Vector3.RIGHT
	var up := Vector3.FORWARD
	if _camera_rig:
		right = _camera_rig.screen_right()
		up = _camera_rig.screen_up()
	var dir := right * v.x + up * (-v.y)
	return dir.normalized() if dir.length_squared() > 1.0 else dir


func _apply_facing(delta: float, instant: bool) -> void:
	var yaw := atan2(-facing.x, -facing.z)
	if instant:
		visual_root.rotation.y = yaw
	else:
		visual_root.rotation.y = lerp_angle(visual_root.rotation.y, yaw, minf(1.0, turn_speed * delta))


func _start_attack() -> void:
	state = State.ATTACK
	_attack_time = 0.0
	_attack_hit_done.clear()


## 방향 입력이 있으면 그쪽으로 보며 점프, 없으면 시선은 그대로 두고 뒤로 백스텝
func _start_dodge(wish_dir: Vector3) -> void:
	state = State.DODGE
	_dodge_time = 0.0
	if wish_dir.length_squared() > 0.0:
		_dodge_dir = wish_dir.normalized()
		facing = _dodge_dir
		_dodge_lean = 1.0
	else:
		_dodge_dir = -facing
		_dodge_lean = -1.0
	velocity.y = dodge_hop


## 전방 100°, 1.45m 안의 attack_targets 를 한 공격당 한 번만 타격
func _do_attack_hitcheck() -> void:
	var cos_half := cos(deg_to_rad(attack_cone_deg * 0.5))
	for node in get_tree().get_nodes_in_group("attack_targets"):
		if _attack_hit_done.has(node):
			continue
		var target := node as Node3D
		if target == null:
			continue
		var to := target.global_position - global_position
		to.y = 0.0
		var radius: float = target.get("hit_radius") if target.get("hit_radius") != null else 0.0
		var dist := to.length()
		if dist > attack_range + radius:
			continue
		var dir := to / maxf(dist, 0.0001)
		if dir.dot(facing) < cos_half and dist > radius:
			continue
		_attack_hit_done[node] = true
		if target.has_method("receive_hit"):
			target.receive_hit(dir)


# ---------------------------------------------------------------- 절차 애니메이션 (뼈 포즈)
# 모델 공간 축: X = 오른쪽, Y = 위, Z = 뒤 (정면 -Z). 오일러 x+ = 앞으로 숙임/다리 뒤로, 등.

func _animate(delta: float, speed_ratio: float) -> void:
	_idle_phase += delta
	if state == State.ATTACK:
		_animate_attack()
		return
	if state == State.DODGE:
		_animate_dodge()
		return

	var walk := clampf(speed_ratio, 0.0, 1.0)
	_walk_phase += delta * 12.0 * maxf(walk, 0.0)
	var s := sin(_walk_phase)
	var c := cos(_walk_phase)
	# 다리: 앞뒤 교차, 뒤로 가는 다리는 무릎을 접는다
	_pose("UpperLeg.L", Vector3(-38.0 * s * walk, 0, 0))
	_pose("UpperLeg.R", Vector3(38.0 * s * walk, 0, 0))
	_pose("LowerLeg.L", Vector3(maxf(0.0, s) * 42.0 * walk, 0, 0))
	_pose("LowerLeg.R", Vector3(maxf(0.0, -s) * 42.0 * walk, 0, 0))
	# 팔: 다리와 반대 위상, 약간 벌림
	_pose("UpperArm.L", Vector3(24.0 * s * walk, 0, -4.0))
	_pose("UpperArm.R", Vector3(-24.0 * s * walk, 0, 4.0))
	_pose("LowerArm.L", Vector3(-10.0 * walk, 0, 0))
	_pose("LowerArm.R", Vector3(-10.0 * walk, 0, 0))
	# 몸통: 걸을 때 앞으로 살짝 숙이고 어깨 비틀기, 정지 시 호흡
	var breathe := sin(_idle_phase * 2.2)
	_pose("Spine", Vector3(-6.0 * walk - 1.2 * breathe * (1.0 - walk), 4.0 * s * walk, 0))
	_pose("Chest", Vector3(-2.0 * walk - 1.0 * breathe * (1.0 - walk), 0, 0))
	_pose("Head", Vector3(3.0 * walk, -3.0 * s * walk, 0))
	_hips_offset(absf(c) * 0.035 * walk + breathe * 0.005 * (1.0 - walk))


## 준비(뒤로 당김) → 타격(앞으로 뻗으며 상체 회전) → 복귀
func _animate_attack() -> void:
	var t := _attack_time
	var lean := 0.0
	var twist := 0.0
	var arm_pitch := 0.0
	var arm_roll := 0.0
	if t < attack_windup_end:
		var k := t / attack_windup_end
		lean = lerpf(0.0, 8.0, k)
		twist = lerpf(0.0, 35.0, k)
		arm_pitch = lerpf(0.0, 60.0, k)
		arm_roll = lerpf(0.0, 40.0, k)
	elif t < attack_active_end:
		var k := (t - attack_windup_end) / (attack_active_end - attack_windup_end)
		var e := 1.0 - pow(1.0 - k, 3.0)
		lean = lerpf(8.0, -14.0, e)
		twist = lerpf(35.0, -45.0, e)
		arm_pitch = lerpf(60.0, -100.0, e)
		arm_roll = lerpf(40.0, -10.0, e)
	else:
		var k := (t - attack_active_end) / (attack_duration - attack_active_end)
		var e := k * k
		lean = lerpf(-14.0, 0.0, e)
		twist = lerpf(-45.0, 0.0, e)
		arm_pitch = lerpf(-100.0, 0.0, e)
		arm_roll = lerpf(-10.0, 0.0, e)
	_pose("Spine", Vector3(lean, twist, 0))
	_pose("Chest", Vector3(lean * 0.4, twist * 0.4, 0))
	_pose("Head", Vector3(0, -twist * 0.5, 0))
	_pose("UpperArm.R", Vector3(arm_pitch, 0, arm_roll))
	_pose("LowerArm.R", Vector3(minf(0.0, arm_pitch) * 0.3, 0, 0))
	_pose("UpperArm.L", Vector3(-arm_pitch * 0.3, 0, -8.0))
	_pose("LowerArm.L", Vector3(-20.0, 0, 0))
	# 발은 넓게 벌려 버틴다
	_pose("UpperLeg.L", Vector3(18.0, 0, -6.0))
	_pose("UpperLeg.R", Vector3(-22.0, 0, 6.0))
	_pose("LowerLeg.L", Vector3(10.0, 0, 0))
	_pose("LowerLeg.R", Vector3(18.0, 0, 0))
	_hips_offset(-0.03)


## 웅크렸다가 몸을 던지는 짧은 점프. 앞으로 뛰면 앞으로, 백스텝이면 뒤로 기운다.
func _animate_dodge() -> void:
	var k := clampf(_dodge_time / dodge_duration, 0.0, 1.0)
	# 0~0.25 웅크림, 0.25~0.8 몸 던짐, 0.8~1 착지
	var crouch := 0.0
	var lean := 0.0
	var tuck := 0.0
	if k < 0.25:
		var e := k / 0.25
		crouch = lerpf(0.0, -0.14, e)
		lean = lerpf(0.0, 10.0, e)
		tuck = lerpf(0.0, 25.0, e)
	elif k < 0.8:
		var e := (k - 0.25) / 0.55
		crouch = lerpf(-0.14, 0.0, e)
		lean = lerpf(10.0, 32.0, e)
		tuck = lerpf(25.0, 55.0, e)
	else:
		var e := (k - 0.8) / 0.2
		crouch = lerpf(0.0, -0.08, e)
		lean = lerpf(32.0, 6.0, e)
		tuck = lerpf(55.0, 10.0, e)
	# 앞 점프: 앞으로 숙임(−x), 백스텝: 뒤로 젖힘(+x)
	_pose("Spine", Vector3(-lean * _dodge_lean, 0, 0))
	_pose("Chest", Vector3(-lean * 0.3 * _dodge_lean, 0, 0))
	# 다리 접기: 앞 점프는 다리를 뒤로 차고, 백스텝은 앞으로 들어 올린다
	_pose("UpperLeg.L", Vector3(tuck * 0.8 * _dodge_lean, 0, 0))
	_pose("UpperLeg.R", Vector3(tuck * _dodge_lean, 0, 0))
	_pose("LowerLeg.L", Vector3(tuck * 0.9, 0, 0))
	_pose("LowerLeg.R", Vector3(tuck * 1.1, 0, 0))
	# 팔은 균형 잡듯 뒤로/옆으로
	_pose("UpperArm.L", Vector3(-tuck * 0.6 * _dodge_lean, 0, -tuck * 0.5))
	_pose("UpperArm.R", Vector3(-tuck * 0.6 * _dodge_lean, 0, tuck * 0.5))
	_hips_offset(crouch)


## 머리카락: 캐릭터 가속도·회전에 뒤처지는 스프링-댐퍼 체인.
## 모델 공간에서 pitch(x) = 앞뒤 흔들림(+ 는 끝이 앞으로), roll(z) = 좌우 흔들림.
func _animate_hair(delta: float, horizontal_vel: Vector3) -> void:
	if _hair_angle.is_empty() or delta <= 0.0:
		return
	# 속도를 캐릭터 로컬(앞/오른쪽)로: 정면 = -Z 모델 → 월드에서는 facing
	var yaw := visual_root.rotation.y
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var vel_local := Vector2(horizontal_vel.dot(right), horizontal_vel.dot(fwd))
	var accel := (vel_local - _prev_vel_local) / delta
	_prev_vel_local = vel_local
	var yaw_rate := wrapf(yaw - _prev_yaw, -PI, PI) / delta
	_prev_yaw = yaw
	# 뿌리 목표: 앞으로 가속하면 머리카락은 뒤로(끝이 뒤 = pitch −), 달리는 동안도 살짝 뒤로.
	var breeze := sin(_idle_phase * 1.7) * hair_breeze_deg
	var root_target := Vector2(
		clampf(-accel.y * hair_accel_gain - vel_local.y * 1.2, -hair_max_deg, hair_max_deg) + breeze,
		clampf(yaw_rate * hair_turn_gain + accel.x * hair_accel_gain * 0.6, -hair_max_deg, hair_max_deg))
	for chain in HAIR_CHAINS:
		var target := root_target
		for n in chain:
			if not _hair_angle.has(n):
				continue
			var a: Vector2 = _hair_angle[n]
			var v: Vector2 = _hair_vel[n]
			v += (target - a) * hair_stiffness * delta - v * hair_damping * delta
			a += v * delta
			a.x = clampf(a.x, -hair_max_deg, hair_max_deg)
			a.y = clampf(a.y, -hair_max_deg, hair_max_deg)
			_hair_angle[n] = a
			_hair_vel[n] = v
			# 각 뼈는 자기 각도만 더한다 (부모 회전은 뼈 계층이 상속) — 체인 끝으로 갈수록 누적
			_pose(n, Vector3(a.x * 0.45, 0.0, a.y * 0.45))
			target = a * hair_follow


func state_name() -> String:
	match state:
		State.IDLE:
			return "IDLE"
		State.WALK:
			return "WALK"
		State.ATTACK:
			return "ATTACK %.2f" % _attack_time
		State.DODGE:
			return "DODGE %.2f" % _dodge_time
	return "?"
