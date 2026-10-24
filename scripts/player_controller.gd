## 플레이어 (GDD §3~5 + 회피 + 무기/퀵슬롯)
## - CharacterBody3D + move_and_slide, 물리 틱에서 이동. 카메라 화면 방향 기준 이동, 대각선 정규화.
## - Z: 현재 무기로 공격. 근접(검)은 0.30 s 휘두르기, 원거리(권총 단발 / 라이플 연사)는 이동 중에도 사격,
##   탄이 떨어지면 자동 재장전. 1~3 = 즉시 무기 교체, 4~5 = 즉시 던지기(단검 직선 / 폭탄 포물선).
## - Shift 회피: 방향키 방향으로 짧은 점프. 입력이 없으면 보는 방향의 반대로 백스텝(시선 유지).
## - 애니메이션: AnimBuilder 키프레임 클립을 AnimationPlayer 로 재생 (Idle/Walk/Attack/Shoot/Throw/Dodge).
class_name PlayerController
extends CharacterBody3D

enum State { IDLE, WALK, ATTACK, DODGE, PARRY, SCRIPTED, FATAL, DEAD }

## Z 3타 연계 (GDD §7): [전체, 유효 시작, 유효 끝, 피해]
const COMBO := [[0.25, 0.09, 0.15, 1], [0.27, 0.08, 0.16, 1], [0.33, 0.12, 0.21, 2]]
const COMBO_BUFFER := 0.10
const COMBO_MOVE_FACTOR := 0.35
const PARRY_LEN := 0.35
## 일반 패턴 패링 활성창 (게임 초) — 패링 시작 후 이 시간 안에 타격이 오면 성공
const PARRY_ACTIVE := 0.20

@export_group("Movement")
@export var move_speed: float = 3.8
@export var acceleration: float = 40.0
@export var deceleration: float = 48.0
@export var gravity: float = 9.8
@export var turn_speed: float = 22.0

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
const MAT_STEEL := preload("res://materials/mat_buckle.tres")
const MAT_DARK := preload("res://materials/mat_belt.tres")
const MAT_FLASH := preload("res://materials/mat_stone_lit.tres")

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
## main 이 넣어 준다. 없으면 기본 인벤토리를 만든다.
var inventory: Inventory
## 보스 전투 (BossTestArena 에서만 설정)
var combat_director: CombatDirector
## 타격 프레임 무적 (시네마틱 회피 성공 시) / 피격 직후 짧은 무적
var invulnerable: bool = false
## 체력 (테스트용: 일반 공격 1회 = 1/3). 치명적 공격은 HP 와 무관하게 즉사
const MAX_HP := 3
var hp: int = MAX_HP
var _hurt_invuln: float = 0.0

var _combo_index: int = 0
var _combo_buffered: bool = false
var _parry_time: float = 0.0
var _scripted_time: float = 0.0
var _scripted_len: float = 0.0
var _scripted_dir: Vector3 = Vector3.ZERO
var _scripted_speed: float = 0.0

var _attack_time: float = 0.0
var _attack_item: Dictionary = {}
var _attack_hit_done: Dictionary = {}
var _dodge_time: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _dodge_cd: float = 0.0
var _fire_cd: float = 0.0
var _reload_left: float = 0.0
var _throw_cd: float = 0.0
var _oneshot_left: float = 0.0   # Shoot/Throw 클립이 재생 중인 남은 시간

@onready var visual_root: Node3D = $VisualRoot
@onready var _model: Node3D = $VisualRoot/Model

var _camera_rig: CameraFollow
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _bones: Dictionary = {}
var _current_anim: String = ""
var _weapon_root: Node3D
var _weapon_meshes: Dictionary = {}   # id → MeshInstance3D
var _muzzle: Node3D


func _ready() -> void:
	floor_snap_length = 0.3
	_camera_rig = get_tree().get_first_node_in_group("camera_rig") as CameraFollow
	if inventory == null:
		inventory = Inventory.new()
		add_child(inventory)
	_setup_model()
	_setup_weapons()
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


## 손에 드는 무기 메시 (단순 박스). 오른손 뼈 위치를 매 프레임 따라간다.
func _setup_weapons() -> void:
	_weapon_root = Node3D.new()
	_weapon_root.name = "WeaponRoot"
	add_child(_weapon_root)
	_weapon_meshes["sword"] = _weapon_box(Vector3(0.035, 0.025, 0.95), Vector3(0.0, 0.02, -0.38), MAT_STEEL)
	_weapon_meshes["pistol"] = _weapon_box(Vector3(0.035, 0.11, 0.2), Vector3(0.0, 0.03, -0.09), MAT_DARK)
	_weapon_meshes["rifle"] = _weapon_box(Vector3(0.045, 0.07, 0.72), Vector3(0.0, 0.04, -0.3), MAT_DARK)
	_muzzle = Node3D.new()
	_muzzle.name = "Muzzle"
	_weapon_root.add_child(_muzzle)
	_refresh_weapon_visual()
	if inventory and not inventory.changed.is_connected(_refresh_weapon_visual):
		inventory.changed.connect(_refresh_weapon_visual)


func _weapon_box(size: Vector3, offset: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = offset
	mi.visible = false
	_weapon_root.add_child(mi)
	return mi


func _refresh_weapon_visual() -> void:
	var active := inventory.active_weapon() if inventory else ""
	for id in _weapon_meshes:
		_weapon_meshes[id].visible = (id == active)
	var d := Items.get_item(active)
	_muzzle.position = Vector3(0.0, 0.04, -0.66) if active == "rifle" else Vector3(0.0, 0.05, -0.2)


func _process(_delta: float) -> void:
	if _skel == null or not _bones.has("Hand.R"):
		return
	# 무기 루트 = 오른손 위치, 방향 = 캐릭터 정면(살짝 아래). 사격/던지기 중엔 수평
	var hand := _skel.global_transform * _skel.get_bone_global_pose(_bones["Hand.R"])
	var fwd := -visual_root.global_transform.basis.z
	var tilt := 0.0 if _oneshot_left > 0.0 else deg_to_rad(28.0)
	var right := fwd.cross(Vector3.UP).normalized()
	var dir := (fwd * cos(tilt) - Vector3.UP * sin(tilt)).normalized()
	var up := right.cross(dir).normalized()
	_weapon_root.global_transform = Transform3D(Basis(right, up, -dir), hand.origin)


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
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_throw_cd = maxf(0.0, _throw_cd - delta)
	_oneshot_left = maxf(0.0, _oneshot_left - delta)
	if _hurt_invuln > 0.0:
		_hurt_invuln -= delta
		if _hurt_invuln <= 0.0 and state != State.SCRIPTED:
			invulnerable = false
	_update_reload(delta)

	# ---- 전투 특수 상태: 입력을 받지 않는다 (치명적 판단은 FatalReactionController 가 처리)
	match state:
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
			velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
			move_and_slide()
			return
		State.FATAL:
			velocity.x = 0.0
			velocity.z = 0.0
			velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
			move_and_slide()
			_apply_facing(delta, false)
			return
		State.SCRIPTED:
			_scripted_time += delta
			var k := 1.0 - clampf(_scripted_time / _scripted_len, 0.0, 1.0)
			velocity = _scripted_dir * _scripted_speed * (0.4 + 1.2 * k)
			velocity.y = 0.0
			move_and_slide()
			_apply_facing(delta, false)
			if _scripted_time >= _scripted_len:
				invulnerable = false
				state = State.IDLE
				DustPuff.spawn(get_parent(), global_position, 1.2)
			return
		State.PARRY:
			_parry_time += delta
			velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
			velocity.y = 0.0
			move_and_slide()
			_apply_facing(delta, false)
			if _parry_time >= PARRY_LEN:
				state = State.IDLE
			return
		_:
			pass

	_handle_quick_slots()

	# 회피: 회피 중이 아니면 언제든 (근접 공격은 유효 타격이 끝난 뒤부터 캔슬 가능)
	if state != State.DODGE and _dodge_cd <= 0.0 and Input.is_action_just_pressed("dodge"):
		if state != State.ATTACK or _attack_time >= float(_attack_item.get("active_end", 0.0)):
			_start_dodge(wish_dir)
	elif state == State.IDLE or state == State.WALK:
		_handle_attack_input()

	# 상태 갱신
	match state:
		State.ATTACK:
			_attack_time += delta
			if _attack_time >= float(_attack_item.get("windup", 0.07)) and _attack_time < float(_attack_item.get("active_end", 0.16)):
				_do_melee_hitcheck()
			# 추가 Z 입력 버퍼: 타격 종료 0.10 s 전부터 예약
			var dur := float(_attack_item.get("duration", 0.3))
			if _attack_item.get("combo", false) and Input.is_action_just_pressed("attack") and _attack_time >= dur - COMBO_BUFFER:
				_combo_buffered = true
			if _attack_time >= dur:
				if _attack_item.get("combo", false) and _combo_buffered and _combo_index < COMBO.size() - 1:
					_start_melee(Items.get_item(inventory.active_weapon()), _combo_index + 1)
				else:
					state = State.IDLE
		State.DODGE:
			_dodge_time += delta
			if _dodge_time >= dodge_duration and (is_on_floor() or _dodge_time > dodge_duration * 2.0):
				state = State.IDLE
				_dodge_cd = dodge_cooldown
				DustPuff.spawn(get_parent(), global_position)
	if state != State.ATTACK and state != State.DODGE:
		state = State.WALK if wish_dir.length_squared() > 0.0 else State.IDLE
		if state == State.WALK:
			facing = wish_dir

	# 수평 속도
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if state == State.DODGE:
		var k := clampf(_dodge_time / dodge_duration, 0.0, 1.0)
		var speed := (dodge_distance / dodge_duration) * 2.0 * (1.0 - k)
		horizontal = _dodge_dir * speed
	else:
		var factor := 1.0
		if state == State.ATTACK:
			factor = float(_attack_item.get("move_factor", 0.6))
		elif _oneshot_left > 0.0:
			factor = float(Items.get_item(inventory.active_weapon()).get("move_factor", 0.85))
		var target_vel := wish_dir * move_speed * factor
		var rate := acceleration if wish_dir.length_squared() > 0.0 else deceleration
		horizontal = horizontal.move_toward(target_vel, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor() and state != State.DODGE:
		velocity.y = 0.0
	else:
		velocity.y -= (dodge_gravity if state == State.DODGE else gravity) * delta

	move_and_slide()

	_apply_facing(delta, false)
	_update_animation(horizontal.length())


# ---------------------------------------------------------------- 무기 / 퀵슬롯

## 1~3: 즉시 무기 교체, 4~5: 즉시 사용(던지기)
func _handle_quick_slots() -> void:
	for i in 5:
		if Input.is_action_just_pressed("quick_%d" % (i + 1)):
			_use_quick(i)


func _use_quick(i: int) -> void:
	var id: String = inventory.quick[i]
	if id == "" or not inventory.has(id):
		return
	var d := Items.get_item(id)
	match d.get("kind"):
		Items.Kind.MELEE, Items.Kind.RANGED:
			if state == State.ATTACK:
				return
			inventory.equip(id)
			_reload_left = 0.0
		Items.Kind.CONSUMABLE:
			_use_consumable(id)


func _handle_attack_input() -> void:
	if Input.is_action_just_pressed("parry"):
		_start_parry()
		return
	var id := inventory.active_weapon()
	var d := Items.get_item(id)
	if d.is_empty():
		return
	if d["kind"] == Items.Kind.MELEE:
		if Input.is_action_just_pressed("attack"):
			_start_melee(d, 0)
	elif d["kind"] == Items.Kind.RANGED:
		var want := Input.is_action_pressed("attack") if bool(d.get("auto", false)) else Input.is_action_just_pressed("attack")
		if want:
			_try_fire(id, d)


## 근접: 검은 3타 연계 (COMBO 표의 시간/피해로 아이템 수치를 덮어쓴다)
func _start_melee(d: Dictionary, combo_index: int = 0) -> void:
	state = State.ATTACK
	_attack_time = 0.0
	_combo_index = combo_index
	_combo_buffered = false
	var item := d.duplicate()
	var c: Array = COMBO[combo_index]
	item["duration"] = c[0]
	item["windup"] = c[1]
	item["active_end"] = c[2]
	item["damage"] = c[3]
	item["move_factor"] = COMBO_MOVE_FACTOR
	item["combo"] = true
	_attack_item = item
	_attack_hit_done.clear()
	_play("Attack%d" % (combo_index + 1), 1.0, true)


func _start_parry() -> void:
	state = State.PARRY
	_parry_time = 0.0
	_play("Parry", 1.0, true)


## 일반 패턴 패링 판정용: 패링 시작 직후 활성창
func is_parry_active() -> bool:
	return state == State.PARRY and _parry_time <= PARRY_ACTIVE


# ---------------------------------------------------------------- 보스 전투 (FatalReactionController / CombatDirector 가 호출)

## 치명적 판단 시작: 공격/후딜/이동을 즉시 인터럽트하고 멈춘다 (순간 대응이 최우선)
func begin_fatal() -> void:
	state = State.FATAL
	_combo_buffered = false
	_oneshot_left = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_play("Brace", 1.0, true)


## 시네마틱 회피 스텝: 화면 방향으로 meters 를 game_seconds 동안. 타격 프레임 무적.
func scripted_dodge(dir: Vector3, meters: float, game_seconds: float) -> void:
	state = State.SCRIPTED
	_scripted_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	_scripted_len = game_seconds
	_scripted_speed = meters / maxf(game_seconds, 0.01)
	_scripted_time = 0.0
	invulnerable = true
	_play("SideStep", 1.0, true)


## 치명적 패턴 패링 성공 연출
func scripted_parry() -> void:
	state = State.PARRY
	_parry_time = 0.0
	velocity = Vector3.ZERO
	_play("Parry", 1.0, true)


## 일반 공격 피격: HP 1 감소, 짧은 무적 + 휘청. 0 이 되면 사망 (호출자가 die 처리)
func take_normal_hit(from_dir: Vector3) -> void:
	hp = maxi(0, hp - 1)
	_hurt_invuln = 0.6
	invulnerable = true
	velocity = from_dir * 4.0
	if state == State.ATTACK or state == State.IDLE or state == State.WALK:
		state = State.PARRY   # 짧은 경직으로 재사용 (0.35 s)
		_parry_time = 0.12    # 패링 활성창은 지나간 상태
		_play("DodgeBack", 1.4, true)


func die() -> void:
	state = State.DEAD
	invulnerable = false
	_combo_buffered = false
	velocity = Vector3.ZERO
	_play("Death", 1.0, true)


## 치명적 상태에서 해제 (보스 승리 등)
func end_combat_lock() -> void:
	if state == State.FATAL or state == State.SCRIPTED:
		state = State.IDLE
	invulnerable = false


## 재도전: 위치/방향/상태/콤보/버퍼/무적/탄 전부 초기화
func reset_for_retry(pos: Vector3, face: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	facing = face.normalized()
	state = State.IDLE
	invulnerable = false
	hp = MAX_HP
	_hurt_invuln = 0.0
	_combo_index = 0
	_combo_buffered = false
	_attack_time = 0.0
	_attack_item = {}
	_dodge_cd = 0.0
	_fire_cd = 0.0
	_reload_left = 0.0
	_throw_cd = 0.0
	_oneshot_left = 0.0
	if inventory:
		for id in inventory.ammo:
			inventory.ammo[id] = int(Items.get_item(id).get("magazine", 1))
		inventory.changed.emit()
	_apply_facing(0.0, true)
	_play("Idle", 1.0, true)


func _try_fire(id: String, d: Dictionary) -> void:
	if _fire_cd > 0.0 or _reload_left > 0.0:
		return
	if int(inventory.ammo.get(id, 0)) <= 0:
		_reload_left = float(d.get("reload", 1.0))
		return
	inventory.ammo[id] = int(inventory.ammo[id]) - 1
	_fire_cd = float(d.get("interval", 0.2))
	# 탄은 손(총구)에서 나가되, 캐릭터 중심선 위 사거리 끝 지점으로 수렴시킨다 (오른손 오프셋 보정)
	var spread := deg_to_rad(float(d.get("spread_deg", 0.0)))
	var from := _muzzle.global_position
	var aim_point := global_position + Vector3(0, from.y - global_position.y, 0) + facing * minf(5.0, float(d.get("range", 10.0)))
	var dir := (aim_point - from).normalized().rotated(Vector3.UP, randf_range(-spread, spread))
	var p := Projectile.make(id, from, dir, d)
	get_parent().add_child(p)
	_muzzle_flash()
	_oneshot("Shoot", AnimBuilder.SHOOT_LEN)
	inventory.changed.emit()
	if int(inventory.ammo[id]) <= 0:
		_reload_left = float(d.get("reload", 1.0))


func _update_reload(delta: float) -> void:
	if _reload_left <= 0.0:
		return
	_reload_left -= delta
	if _reload_left <= 0.0:
		var id := inventory.active_weapon()
		var d := Items.get_item(id)
		if d.get("kind") == Items.Kind.RANGED:
			inventory.ammo[id] = int(d.get("magazine", 1))
			inventory.changed.emit()


func _use_consumable(id: String) -> void:
	if _throw_cd > 0.0 or state == State.ATTACK or state == State.DODGE:
		return
	var d := Items.get_item(id)
	if not inventory.consume(id):
		return
	_throw_cd = float(d.get("cooldown", 0.3))
	var from := global_position + Vector3(0, 1.25, 0) + facing * 0.4
	var p := Projectile.make(id, from, facing, d)
	get_parent().add_child(p)
	_oneshot("Throw", AnimBuilder.THROW_LEN)


func _oneshot(clip: String, length: float) -> void:
	# 서 있을 때만 상체 클립 재생 (이동 중엔 걷기 유지 — 속도 우선)
	if state == State.IDLE or state == State.WALK and velocity.length() < 0.6:
		_play(clip, 1.0, true)
	_oneshot_left = length


func _muzzle_flash() -> void:
	var f := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.09
	m.height = 0.18
	m.radial_segments = 8
	m.rings = 4
	f.mesh = m
	f.material_override = MAT_FLASH
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(f)
	f.global_position = _muzzle.global_position
	get_tree().create_timer(0.05).timeout.connect(f.queue_free)


## HUD 용 한 줄
func weapon_status_text() -> String:
	if inventory == null:
		return ""
	var id := inventory.active_weapon()
	var d := Items.get_item(id)
	if d.is_empty():
		return "-"
	var s: String = d["name"]
	if d["kind"] == Items.Kind.RANGED:
		if _reload_left > 0.0:
			s += "  재장전 %.1f" % _reload_left
		else:
			s += "  %d / %d" % [int(inventory.ammo.get(id, 0)), int(d["magazine"])]
	s += "     단검 ×%d   폭탄 ×%d" % [inventory.count("dagger"), inventory.count("bomb")]
	return s


# ---------------------------------------------------------------- 애니메이션 / 이동 / 회피

## 상태 → 애니메이션. Walk 는 이동 속도에 맞춰 재생 속도 조절 (발 미끄러짐 최소화)
func _update_animation(speed: float) -> void:
	match state:
		State.WALK, State.IDLE:
			if _oneshot_left > 0.0 and _current_anim in ["Shoot", "Throw"]:
				return
			if speed > 0.4:
				_play("Walk", clampf(speed / move_speed * 1.12, 0.35, 1.5))
			else:
				_play("Idle")
		_:
			pass


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


## 전방 부채꼴 안의 attack_targets 를 한 공격당 한 번만 타격
func _do_melee_hitcheck() -> void:
	var cos_half := cos(deg_to_rad(float(_attack_item.get("cone_deg", 100.0)) * 0.5))
	var reach := float(_attack_item.get("range", 1.45))
	var dmg := int(_attack_item.get("damage", 1))
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
		if dist > reach + radius:
			continue
		var dir := to / maxf(dist, 0.0001)
		if dir.dot(facing) < cos_half and dist > radius:
			continue
		_attack_hit_done[node] = true
		if target.has_method("receive_hit"):
			target.receive_hit(dir, dmg)


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
		State.PARRY:
			return "PARRY %.2f" % _parry_time
		State.SCRIPTED:
			return "SCRIPTED_DODGE %.2f" % _scripted_time
		State.FATAL:
			return "FATAL_DECISION"
		State.DEAD:
			return "DEAD"
	return "?"
