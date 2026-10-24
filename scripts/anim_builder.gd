## 키프레임 애니메이션 생성기 — Idle / Walk / Attack / DodgeFwd / DodgeBack
##
## 포즈는 '모델 공간' 오일러(도)로 설계한다 (모델 정면 = -Z, X+ = 팔다리 앞으로 / 상체 뒤로 젖힘, Y+ = 요, Z+ = 롤).
## build_library() 가 스켈레톤 rest 를 이용해 뼈 로컬 쿼터니언 트랙으로 변환하므로 뼈 롤/축 방향과 무관하다.
## 사이클은 30fps 로 샘플링한 키, 원샷은 설계 키프레임을 큐빅 보간.
class_name AnimBuilder
extends RefCounted

const FPS := 30.0
const WALK_CYCLE := 0.62   # 두 걸음 (초) — 보폭 ~1.4 m × 2 / 4.8 m/s
const IDLE_CYCLE := 6.0
const ATTACK_LEN := 0.30
const DODGE_LEN := 0.40

var _skel: Skeleton3D
var _bones: Dictionary       # 논리 이름 → 뼈 인덱스
var _rest_local: Dictionary
var _rest_global: Dictionary
var _hips_rest: Vector3
var _skel_path: String


func _init(skel: Skeleton3D, bones: Dictionary, skel_path: String) -> void:
	_skel = skel
	_bones = bones
	_skel_path = skel_path
	for n in bones:
		var i: int = bones[n]
		_rest_local[n] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
		_rest_global[n] = skel.get_bone_global_rest(i).basis.get_rotation_quaternion()
	if bones.has("Hips"):
		_hips_rest = skel.get_bone_rest(bones["Hips"]).origin


func build_library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation("Idle", _sampled("Idle", IDLE_CYCLE, _idle_pose, true))
	lib.add_animation("Walk", _sampled("Walk", WALK_CYCLE, _walk_pose, true))
	lib.add_animation("Attack", _keyed("Attack", ATTACK_LEN, _attack_keys()))
	lib.add_animation("DodgeFwd", _keyed("DodgeFwd", DODGE_LEN, _dodge_keys(1.0)))
	lib.add_animation("DodgeBack", _keyed("DodgeBack", DODGE_LEN, _dodge_keys(-1.0)))
	return lib


# ---------------------------------------------------------------- 포즈 설계
# 반환: {"bone": Vector3(x,y,z) 도, ..., "hips_pos": Vector3 오프셋(m)}

## 보행 사이클. t∈[0,1): 0 = 왼발 접지, 0.5 = 오른발 접지.
## 접지→하강(무릎 살짝 굽힘)→통과(골반 최고, 반대 다리 무릎 최대 굽힘)→상승→반대발 접지
func _walk_pose(t: float) -> Dictionary:
	var w := TAU * t
	var p := {}
	# 허벅지: 앞뒤 스윙 ±30°, 접지 직전이 최대 앞
	var thigh := 27.0 * cos(w) + 3.0
	p["UpperLeg.L"] = Vector3(thigh, 0.0, -2.0)
	p["UpperLeg.R"] = Vector3(-thigh, 0.0, 2.0)
	# 무릎: 스윙 중(다리가 뒤에서 앞으로 올 때) 최대 55°, 접지 하중기에 12°
	p["LowerLeg.L"] = Vector3(-(8.0 + 34.0 * pow(maxf(0.0, sin(w - PI)), 1.6) + 8.0 * maxf(0.0, cos(w + 0.6))), 0.0, 0.0)
	p["LowerLeg.R"] = Vector3(-(8.0 + 34.0 * pow(maxf(0.0, sin(w)), 1.6) + 8.0 * maxf(0.0, cos(w + PI + 0.6))), 0.0, 0.0)
	# 발: 뒤로 차고 나갈 때 발끝 내림(+), 접지 직전 발끝 들림(−)
	p["Foot.L"] = Vector3(14.0 * sin(w + 0.3) - 4.0, 0.0, 0.0)
	p["Foot.R"] = Vector3(14.0 * sin(w + PI + 0.3) - 4.0, 0.0, 0.0)
	# 골반: 통과기에 높고 접지에 낮음(주기 2배), 지지 다리 쪽으로 좌우 이동, 앞 다리 쪽이 앞으로 회전
	p["hips_pos"] = Vector3(-0.018 * sin(w), -0.022 * cos(2.0 * w) - 0.01, 0.0)
	p["Hips"] = Vector3(0.0, -7.0 * cos(w), 3.0 * sin(w))
	# 상체: 앞으로 살짝 숙이고 골반 반대 방향으로 비틀기 (팔 스윙과 같은 방향)
	p["Spine"] = Vector3(-4.0, 3.0 * cos(w), -1.5 * sin(w))
	p["Chest"] = Vector3(-2.0 + 1.0 * cos(2.0 * w), 5.0 * cos(w), -1.0 * sin(w))
	p["Neck"] = Vector3(1.0, -2.0 * cos(w), 0.0)
	p["Head"] = Vector3(2.0 - 1.0 * cos(2.0 * w), -3.0 * cos(w), 0.0)
	# 팔: 다리와 반대 위상, 앞으로 올 때 팔꿈치 더 굽힘, 살짝 벌림
	var arm := 26.0 * cos(w)
	p["Shoulder.L"] = Vector3(0.0, 2.0 * cos(w), 0.0)
	p["Shoulder.R"] = Vector3(0.0, 2.0 * cos(w), 0.0)
	p["UpperArm.L"] = Vector3(-arm - 2.0, 0.0, -7.0)
	p["UpperArm.R"] = Vector3(arm - 2.0, 0.0, 7.0)
	p["LowerArm.L"] = Vector3(14.0 + 16.0 * maxf(0.0, -cos(w)), 0.0, 0.0)
	p["LowerArm.R"] = Vector3(14.0 + 16.0 * maxf(0.0, cos(w)), 0.0, 0.0)
	p["Hand.L"] = Vector3(0.0, 0.0, 0.0)
	p["Hand.R"] = Vector3(0.0, 0.0, 0.0)
	return p


## 대기: 호흡(3 s) + 느린 체중 이동/둘러보기(6 s)
func _idle_pose(t: float) -> Dictionary:
	var b := sin(TAU * t / 3.0)           # 호흡
	var s := sin(TAU * t / 6.0)           # 체중 이동
	var look := sin(TAU * t / 6.0 + 1.2)  # 둘러보기
	var p := {}
	p["hips_pos"] = Vector3(0.012 * s, 0.005 * b, 0.0)
	p["Hips"] = Vector3(0.0, 1.5 * s, 2.0 * s)
	p["Spine"] = Vector3(-1.5 - 1.0 * b, -1.0 * s, -1.0 * s)
	p["Chest"] = Vector3(-1.0 - 2.0 * b, 0.0, 0.0)
	p["Neck"] = Vector3(0.5 * b, 0.0, 0.0)
	p["Head"] = Vector3(1.0 + 1.0 * b, 6.0 * pow(look, 3.0), 1.5 * s)
	p["Shoulder.L"] = Vector3(0.0, 0.0, 1.0 * b)
	p["Shoulder.R"] = Vector3(0.0, 0.0, -1.0 * b)
	p["UpperArm.L"] = Vector3(2.0 + 1.5 * b, 0.0, -4.0 - 1.5 * b)
	p["UpperArm.R"] = Vector3(2.0 + 1.5 * b, 0.0, 4.0 + 1.5 * b)
	p["LowerArm.L"] = Vector3(10.0 + 2.0 * b, 0.0, 0.0)
	p["LowerArm.R"] = Vector3(10.0 + 2.0 * b, 0.0, 0.0)
	p["UpperLeg.L"] = Vector3(0.0, 0.0, -1.0 - 1.0 * s)
	p["UpperLeg.R"] = Vector3(0.0, 0.0, 1.0 - 1.0 * s)
	p["LowerLeg.L"] = Vector3(-3.0 + 1.0 * s, 0.0, 0.0)
	p["LowerLeg.R"] = Vector3(-3.0 - 1.0 * s, 0.0, 0.0)
	return p


## 공격: [시간, 포즈] 키. 준비(뒤로 당김, 상체 뒤로) → 타격(오른팔 앞으로 뻗으며 상체 앞으로·비틀기) → 복귀
func _attack_keys() -> Array:
	var neutral := {"Spine": Vector3(-2, 0, 0), "Chest": Vector3(-1, 0, 0), "Head": Vector3(1, 0, 0),
		"UpperArm.L": Vector3(2, 0, -4), "UpperArm.R": Vector3(2, 0, 4), "LowerArm.L": Vector3(10, 0, 0), "LowerArm.R": Vector3(10, 0, 0),
		"UpperLeg.L": Vector3(0, 0, -1), "UpperLeg.R": Vector3(0, 0, 1), "LowerLeg.L": Vector3(-3, 0, 0), "LowerLeg.R": Vector3(-3, 0, 0),
		"hips_pos": Vector3.ZERO}
	var windup := {"Spine": Vector3(5, -28, 0), "Chest": Vector3(3, -12, 0), "Head": Vector3(0, 14, 0),
		"UpperArm.L": Vector3(20, 0, -10), "UpperArm.R": Vector3(-45, 0, 45), "LowerArm.L": Vector3(30, 0, 0), "LowerArm.R": Vector3(70, 0, 0),
		"UpperLeg.L": Vector3(14, 0, -6), "UpperLeg.R": Vector3(-16, 0, 8), "LowerLeg.L": Vector3(-14, 0, 0), "LowerLeg.R": Vector3(-20, 0, 0),
		"hips_pos": Vector3(0, -0.03, 0)}
	var strike := {"Spine": Vector3(-14, 32, 0), "Chest": Vector3(-6, 14, 0), "Head": Vector3(-4, -12, 0),
		"UpperArm.L": Vector3(-25, 0, -8), "UpperArm.R": Vector3(96, 0, 6), "LowerArm.L": Vector3(20, 0, 0), "LowerArm.R": Vector3(4, 0, 0),
		"UpperLeg.L": Vector3(20, 0, -6), "UpperLeg.R": Vector3(-24, 0, 8), "LowerLeg.L": Vector3(-18, 0, 0), "LowerLeg.R": Vector3(-26, 0, 0),
		"hips_pos": Vector3(0, -0.05, -0.06)}
	var settle := {"Spine": Vector3(-6, 10, 0), "Chest": Vector3(-3, 4, 0), "Head": Vector3(0, -4, 0),
		"UpperArm.L": Vector3(-6, 0, -6), "UpperArm.R": Vector3(40, 0, 6), "LowerArm.L": Vector3(14, 0, 0), "LowerArm.R": Vector3(20, 0, 0),
		"UpperLeg.L": Vector3(8, 0, -3), "UpperLeg.R": Vector3(-10, 0, 4), "LowerLeg.L": Vector3(-8, 0, 0), "LowerLeg.R": Vector3(-10, 0, 0),
		"hips_pos": Vector3(0, -0.02, -0.02)}
	return [[0.0, neutral], [0.07, windup], [0.16, strike], [0.22, settle], [ATTACK_LEN, neutral]]


## 회피: 웅크림 → 몸 던지기(앞: 앞으로 숙이고 다리 뒤로 / 뒤: 뒤로 젖히고 다리 앞으로) → 착지 웅크림 → 복귀
func _dodge_keys(dir: float) -> Array:
	var neutral := {"Spine": Vector3(-2, 0, 0), "Chest": Vector3(-1, 0, 0), "Head": Vector3(1, 0, 0),
		"UpperArm.L": Vector3(2, 0, -4), "UpperArm.R": Vector3(2, 0, 4), "LowerArm.L": Vector3(10, 0, 0), "LowerArm.R": Vector3(10, 0, 0),
		"UpperLeg.L": Vector3(0, 0, -1), "UpperLeg.R": Vector3(0, 0, 1), "LowerLeg.L": Vector3(-3, 0, 0), "LowerLeg.R": Vector3(-3, 0, 0),
		"hips_pos": Vector3.ZERO}
	var crouch := {"Spine": Vector3(-18 * dir, 0, 0), "Chest": Vector3(-8 * dir, 0, 0), "Head": Vector3(10 * dir, 0, 0),
		"UpperArm.L": Vector3(-20 * dir, 0, -14), "UpperArm.R": Vector3(-20 * dir, 0, 14), "LowerArm.L": Vector3(30, 0, 0), "LowerArm.R": Vector3(30, 0, 0),
		"UpperLeg.L": Vector3(40, 0, -8), "UpperLeg.R": Vector3(40, 0, 8), "LowerLeg.L": Vector3(-60, 0, 0), "LowerLeg.R": Vector3(-60, 0, 0),
		"hips_pos": Vector3(0, -0.16, 0)}
	var leap := {"Spine": Vector3(-28 * dir, 0, 0), "Chest": Vector3(-10 * dir, 0, 0), "Head": Vector3(14 * dir, 0, 0),
		"UpperArm.L": Vector3(-45 * dir, 0, -30), "UpperArm.R": Vector3(-45 * dir, 0, 30), "LowerArm.L": Vector3(20, 0, 0), "LowerArm.R": Vector3(20, 0, 0),
		"UpperLeg.L": Vector3(-30 * dir + 10, 0, -6), "UpperLeg.R": Vector3(-30 * dir - 10, 0, 6), "LowerLeg.L": Vector3(-50, 0, 0), "LowerLeg.R": Vector3(-40, 0, 0),
		"hips_pos": Vector3(0, 0.02, 0)}
	var land := {"Spine": Vector3(-12 * dir, 0, 0), "Chest": Vector3(-5 * dir, 0, 0), "Head": Vector3(6 * dir, 0, 0),
		"UpperArm.L": Vector3(-10 * dir, 0, -12), "UpperArm.R": Vector3(-10 * dir, 0, 12), "LowerArm.L": Vector3(24, 0, 0), "LowerArm.R": Vector3(24, 0, 0),
		"UpperLeg.L": Vector3(28, 0, -8), "UpperLeg.R": Vector3(24, 0, 8), "LowerLeg.L": Vector3(-46, 0, 0), "LowerLeg.R": Vector3(-40, 0, 0),
		"hips_pos": Vector3(0, -0.12, 0)}
	return [[0.0, neutral], [0.06, crouch], [0.16, leap], [0.28, land], [DODGE_LEN, neutral]]


# ---------------------------------------------------------------- Animation 리소스 생성

func _sampled(n: String, length: float, pose_fn: Callable, looping: bool) -> Animation:
	var anim := Animation.new()
	anim.resource_name = n
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var tracks := _make_tracks(anim)
	var frames := int(round(length * FPS))
	for f in frames + (0 if looping else 1):
		var time := float(f) / FPS
		var t := time / length
		_insert_pose(anim, tracks, time, pose_fn.call(t))
	if looping:
		# 마지막 키를 첫 포즈로 닫아 끊김 방지
		_insert_pose(anim, tracks, length, pose_fn.call(0.0))
	return anim


func _keyed(n: String, length: float, keys: Array) -> Animation:
	var anim := Animation.new()
	anim.resource_name = n
	anim.length = length
	anim.loop_mode = Animation.LOOP_NONE
	var tracks := _make_tracks(anim)
	for k in keys:
		_insert_pose(anim, tracks, k[0], k[1])
	for ti in tracks.values():
		anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_CUBIC)
	return anim


func _make_tracks(anim: Animation) -> Dictionary:
	var tracks := {}
	for n in _bones:
		var ti := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(ti, NodePath("%s:%s" % [_skel_path, _skel.get_bone_name(_bones[n])]))
		tracks[n] = ti
	if _bones.has("Hips"):
		var pi := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(pi, NodePath("%s:%s" % [_skel_path, _skel.get_bone_name(_bones["Hips"])]))
		tracks["hips_pos"] = pi
	return tracks


func _insert_pose(anim: Animation, tracks: Dictionary, time: float, pose: Dictionary) -> void:
	for n in _bones:
		var e: Vector3 = pose.get(n, Vector3.ZERO)
		anim.rotation_track_insert_key(tracks[n], time, _local_rot(n, e))
	if tracks.has("hips_pos"):
		anim.position_track_insert_key(tracks["hips_pos"], time, _hips_rest + pose.get("hips_pos", Vector3.ZERO))


## 모델 공간 오일러(도) → 뼈 로컬 포즈 회전
func _local_rot(n: String, euler_deg: Vector3) -> Quaternion:
	var r := Quaternion.from_euler(Vector3(deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)))
	var g: Quaternion = _rest_global[n]
	return (_rest_local[n] as Quaternion) * (g.inverse() * r * g)
