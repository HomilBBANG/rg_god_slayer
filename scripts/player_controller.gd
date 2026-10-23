## 플레이어 (GDD §3~5 + 회피)
## - CharacterBody3D + move_and_slide, 물리 틱에서 이동
## - 카메라 화면 방향 기준 4방향/대각선 이동, 대각선 정규화. 가속/감속이 커서 즉답에 가깝다.
## - Z 단발 근접 공격 (0.30s: 준비 0.07 / 타격 0.07~0.16 / 복귀 ~0.30)
## - Shift 회피: 방향키 방향으로 짧은 점프. 입력이 없으면 보는 방향의 반대로 백스텝(시선은 정면 유지).
## - Idle / Walk / Attack / Dodge 는 VisualRoot 아래 피벗을 돌리는 절차 애니메이션
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
## Blender 모델(player_red.glb)의 엠프티 계층을 피벗으로 쓴다
@onready var _model: Node3D = $VisualRoot/Model
@onready var _body: Node3D = $VisualRoot/Model/Body
@onready var _torso: Node3D = $VisualRoot/Model/Body/Torso
@onready var _hip_l: Node3D = $VisualRoot/Model/Body/HipL
@onready var _hip_r: Node3D = $VisualRoot/Model/Body/HipR
@onready var _shoulder_l: Node3D = $VisualRoot/Model/Body/Torso/ShoulderL
@onready var _shoulder_r: Node3D = $VisualRoot/Model/Body/Torso/ShoulderR

var _camera_rig: CameraFollow


func _ready() -> void:
	floor_snap_length = 0.3
	EnvAssets.apply_materials(_model)
	_camera_rig = get_tree().get_first_node_in_group("camera_rig") as CameraFollow
	_apply_facing(0.0, true)


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
	_animate(delta, horizontal.length() / move_speed)


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


## 절차 애니메이션 — 큰 덩어리의 자세 변화만. speed_ratio 0~1
func _animate(delta: float, speed_ratio: float) -> void:
	_idle_phase += delta
	if state == State.ATTACK:
		_animate_attack()
		return
	if state == State.DODGE:
		_animate_dodge()
		return

	var walk_amount := clampf(speed_ratio, 0.0, 1.0)
	_walk_phase += delta * 12.0 * maxf(walk_amount, 0.0)
	var s := sin(_walk_phase)
	var leg := deg_to_rad(36.0) * s * walk_amount
	var arm := deg_to_rad(24.0) * s * walk_amount
	_hip_l.rotation.x = leg
	_hip_r.rotation.x = -leg
	_shoulder_l.rotation.x = -arm
	_shoulder_r.rotation.x = arm
	_shoulder_l.rotation.z = 0.0
	_shoulder_r.rotation.z = 0.0
	# 걸을 때 몸 상하 바운스 + 상체 살짝 숙임, 정지 시 호흡
	var bob := absf(cos(_walk_phase)) * 0.04 * walk_amount
	var breathe := sin(_idle_phase * 2.2) * 0.006 * (1.0 - walk_amount)
	_body.position.y = bob + breathe
	_torso.rotation.x = deg_to_rad(7.0) * walk_amount + deg_to_rad(1.5) * sin(_idle_phase * 2.2) * (1.0 - walk_amount)
	_torso.rotation.y = deg_to_rad(4.0) * s * walk_amount


## 준비(뒤로 당김) → 타격(앞으로 뻗으며 상체 회전) → 복귀
func _animate_attack() -> void:
	var t := _attack_time
	var lean := 0.0
	var twist := 0.0
	var arm_pitch := 0.0
	var arm_roll := 0.0
	if t < attack_windup_end:
		var k := t / attack_windup_end
		lean = lerpf(0.0, -8.0, k)
		twist = lerpf(0.0, 35.0, k)
		arm_pitch = lerpf(0.0, 70.0, k)
		arm_roll = lerpf(0.0, -40.0, k)
	elif t < attack_active_end:
		var k := (t - attack_windup_end) / (attack_active_end - attack_windup_end)
		var e := 1.0 - pow(1.0 - k, 3.0)
		lean = lerpf(-8.0, 14.0, e)
		twist = lerpf(35.0, -45.0, e)
		arm_pitch = lerpf(70.0, -95.0, e)
		arm_roll = lerpf(-40.0, 10.0, e)
	else:
		var k := (t - attack_active_end) / (attack_duration - attack_active_end)
		var e := k * k
		lean = lerpf(14.0, 0.0, e)
		twist = lerpf(-45.0, 0.0, e)
		arm_pitch = lerpf(-95.0, 0.0, e)
		arm_roll = lerpf(10.0, 0.0, e)
	_torso.rotation.x = deg_to_rad(lean)
	_torso.rotation.y = deg_to_rad(twist)
	_shoulder_r.rotation.x = deg_to_rad(arm_pitch)
	_shoulder_r.rotation.z = deg_to_rad(arm_roll)
	_shoulder_l.rotation.x = deg_to_rad(-arm_pitch * 0.3)
	_shoulder_l.rotation.z = 0.0
	# 발은 넓게 벌려 버틴다
	_hip_l.rotation.x = deg_to_rad(-18.0)
	_hip_r.rotation.x = deg_to_rad(22.0)
	_body.position.y = 0.0


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
	_body.position.y = crouch
	_torso.rotation.x = deg_to_rad(lean * _dodge_lean)
	_torso.rotation.y = 0.0
	# 다리 접기: 앞 점프는 뒷다리를 접고, 백스텝은 양다리를 앞으로 차올린다
	_hip_l.rotation.x = deg_to_rad(-tuck * 0.8 * _dodge_lean)
	_hip_r.rotation.x = deg_to_rad(-tuck * _dodge_lean)
	# 팔은 균형 잡듯 뒤로
	_shoulder_l.rotation.x = deg_to_rad(tuck * 0.6 * _dodge_lean)
	_shoulder_r.rotation.x = deg_to_rad(tuck * 0.6 * _dodge_lean)
	_shoulder_l.rotation.z = deg_to_rad(-tuck * 0.4)
	_shoulder_r.rotation.z = deg_to_rad(tuck * 0.4)


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
