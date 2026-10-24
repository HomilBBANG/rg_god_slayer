## 플레이어 (GDD §3~5 + 회피)
## - CharacterBody3D + move_and_slide, 물리 틱에서 이동
## - 카메라 화면 방향 기준 4방향/대각선 이동, 대각선 정규화. 가속/감속이 커서 즉답에 가깝다.
## - Z 단발 근접 공격 (0.30s: 준비 0.07 / 타격 0.07~0.16 / 복귀 ~0.30)
## - Shift 회피: 방향키 방향으로 짧은 점프. 입력이 없으면 보는 방향의 반대로 백스텝(시선은 정면 유지).
## - 애니메이션: 사용자가 제공한 리깅 모델(player_src.glb, Mixamo 뼈대)의 Skeleton3D 를
##   AnimBuilder 가 만든 키프레임 애니메이션(Idle/Walk/Attack/DodgeFwd/DodgeBack)으로 AnimationPlayer 가 구동.
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

@export_group("Model")
## 모델 키를 이 값(m)으로 맞춘다 (메시 AABB 기준)
@export var model_height: float = 1.70
## 애니메이션 전환 블렌드 (초)
@export var blend_time: float = 0.12

const CHAR_MAT := preload("res://materials/mat_char.tres")

## 논리 이름 → 실제 뼈 이름 후보 (Godot 은 ':' 를 '_' 로 바꿔 가져온다)
const BONE_MAP := {
	"Hips": "Hips", "Spine": "Spine", "Chest": "Spine2", "Neck": "Neck", "Head": "Head",
	"Shoulder.L": "LeftShoulder", "UpperArm.L": "LeftArm", "LowerArm.L": "LeftForeArm", "Hand.L": "LeftHand",
	"Shoulder.R": "RightShoulder", "UpperArm.R": "RightArm", "LowerArm.R": "RightForeArm", "Hand.R": "RightHand",
	"UpperLeg.L": "LeftUpLeg", "LowerLeg.L": "LeftLeg", "Foot.L": "LeftFoot",
	"UpperLeg.R": "RightUpLeg", "LowerLeg.R": "RightLeg", "Foot.R": "RightFoot",
}
const BONE_PREFIXES := ["mixamorig_", "mixamorig:", ""]

var state: State = State.IDLE
var facing: Vector3 = Vector3(0, 0, 1)
var move_input: Vector2 = Vector2.ZERO

var _attack_time: float = 0.0
var _attack_hit_done: Dictionary = {}
var _dodge_time: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _dodge_cd: float = 0.0

@onready var visual_root: Node3D = $VisualRoot
@onready var _model: Node3D = $VisualRoot/Model

var _camera_rig: CameraFollow
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _bones: Dictionary = {}
var _current_anim: String = ""


func _ready() -> void:
	floor_snap_length = 0.3
	_camera_rig = get_tree().get_first_node_in_group("camera_rig") as CameraFollow
	_setup_model()
	_apply_facing(0.0, true)


## 모델: 머티리얼 치환, 키 맞춤(발 y=0), 뼈 찾기, 애니메이션 생성
func _setup_model() -> void:
	var meshes := _model.find_children("*", "MeshInstance3D", true, false)
	var aabb := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, CHAR_MAT)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var a := mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	if not first and aabb.size.y > 0.001:
		var s := model_height / aabb.size.y
		_model.scale = Vector3.ONE * s
		_model.position.y = -aabb.position.y * s
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_error("[Player] Skeleton3D not found in model")
		return
	_skel = found[0] as Skeleton3D
	for logical in BONE_MAP:
		var idx := -1
		for pre in BONE_PREFIXES:
			idx = _skel.find_bone(pre + BONE_MAP[logical])
			if idx >= 0:
				break
		if idx < 0:
			push_warning("[Player] bone missing: %s" % BONE_MAP[logical])
			continue
		_bones[logical] = idx
	_anim = AnimationPlayer.new()
	_anim.name = "AnimationPlayer"
	add_child(_anim)
	var builder := AnimBuilder.new(_skel, _bones, String(get_path_to(_skel)))
	_anim.add_animation_library("", builder.build_library())
	_anim.playback_default_blend_time = blend_time
	_play("Idle")
	print("[Player] model ready: bones=%d scale=%.3f anims=%s" % [_bones.size(), _model.scale.x, _anim.get_animation_list()])


func _play(n: String, speed: float = 1.0, restart: bool = false) -> void:
	if _anim == null:
		return
	_anim.speed_scale = speed
	if _current_anim == n and not restart:
		return
	_anim.play(n, blend_time)
	_current_anim = n


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
	_update_animation(horizontal.length())


## 상태 → 애니메이션. Walk 는 이동 속도에 맞춰 재생 속도 조절 (발 미끄러짐 최소화)
func _update_animation(speed: float) -> void:
	match state:
		State.WALK:
			_play("Walk", clampf(speed / move_speed, 0.35, 1.4))
		State.IDLE:
			if speed > 0.4:
				_play("Walk", clampf(speed / move_speed, 0.35, 1.4))
			else:
				_play("Idle")
		State.ATTACK:
			_play("Attack", AnimBuilder.ATTACK_LEN / attack_duration)
		State.DODGE:
			_play("DodgeFwd" if _dodge_dir.dot(facing) > 0.0 else "DodgeBack")


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
	_play("Attack", AnimBuilder.ATTACK_LEN / attack_duration, true)


## 방향 입력이 있으면 그쪽으로 보며 점프, 없으면 시선은 그대로 두고 뒤로 백스텝
func _start_dodge(wish_dir: Vector3) -> void:
	state = State.DODGE
	_dodge_time = 0.0
	if wish_dir.length_squared() > 0.0:
		_dodge_dir = wish_dir.normalized()
		facing = _dodge_dir
	else:
		_dodge_dir = -facing
	velocity.y = dodge_hop
	_play("DodgeFwd" if _dodge_dir.dot(facing) > 0.0 else "DodgeBack", 1.0, true)


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
