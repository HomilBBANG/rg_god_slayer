## 키프레임 애니메이션 생성기 — Idle / Walk / Attack / DodgeFwd / DodgeBack
##
## 포즈는 '모델 공간' 오일러(도)로 설계한다 (모델 정면 = -Z, X+ = 팔다리 앞으로 / 상체 뒤로 젖힘, Y+ = 요, Z+ = 롤).
## build_library() 가 스켈레톤 rest 를 이용해 뼈 로컬 쿼터니언 트랙으로 변환하므로 뼈 롤/축 방향과 무관하다.
## 사이클은 30fps 로 샘플링한 키, 원샷은 설계 키프레임을 큐빅 보간.
class_name AnimBuilder
extends RefCounted

const FPS := 30.0
const WALK_CYCLE := 0.56   # 두 걸음 (초) — 보폭 ~0.85 m × 2 ≈ 1.7 m / 3.8 m/s ≈ 0.45 s (살짝 느리게 잡아 급한 느낌 완화)
const IDLE_CYCLE := 6.0
const ATTACK_LEN := 0.30
const DODGE_LEN := 0.40
const SHOOT_LEN := 0.16
const THROW_LEN := 0.30

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
	# Z 3타 (GDD §7: 0.25 / 0.27 / 0.33 s). 2타는 반대쪽에서 들어오는 역베기, 3타는 크게 내려치는 강타
	lib.add_animation("Attack1", _keyed("Attack1", 0.25, _scaled_keys(_attack_keys(), 0.25 / ATTACK_LEN)))
	lib.add_animation("Attack2", _keyed("Attack2", 0.27, _scaled_keys(_mirror_yaw(_attack_keys()), 0.27 / ATTACK_LEN)))
	lib.add_animation("Attack3", _keyed("Attack3", 0.33, _heavy_keys()))
	lib.add_animation("Parry", _keyed("Parry", 0.35, _parry_keys()))
	lib.add_animation("SideStep", _keyed("SideStep", 0.30, _scaled_keys(_dodge_keys(1.0), 0.30 / DODGE_LEN)))
	lib.add_animation("Brace", _keyed("Brace", 0.20, _brace_keys()))
	lib.add_animation("Death", _keyed("Death", 0.60, _death_keys()))
	lib.add_animation("DodgeFwd", _keyed("DodgeFwd", DODGE_LEN, _dodge_keys(1.0)))
	lib.add_animation("DodgeBack", _keyed("DodgeBack", DODGE_LEN, _dodge_keys(-1.0)))
	lib.add_animation("Shoot", _keyed("Shoot", SHOOT_LEN, _shoot_keys()))
	lib.add_animation("Throw", _keyed("Throw", THROW_LEN, _throw_keys()))
	return lib


# ---------------------------------------------------------------- 포즈 설계
# 반환: {"bone": Vector3(x,y,z) 도, ..., "hips_pos": Vector3 오프셋(m)}

## 보행 사이클. t∈[0,1): 0 = 왼발 뒤꿈치 접지, 0.5 = 오른발 접지.
## 관절각은 임상 보행 데이터 형태를 근사: 고관절 +30°(접지)→−15°(발끝 떼기 60%)→+30°,
## 무릎 접지 5° → 하중기 18°(12%) → 중간입각 5°(40%) → 발끝 떼기 40°(60%) → 스윙 최대 62°(72%) → 5°,
## 발목 발끝 떼기(58%)에 저측굴곡 −18°, 접지 직전 배측굴곡 +6°.
func _walk_pose(t: float) -> Dictionary:
	var w := TAU * t
	var p := {}
	p["UpperLeg.L"] = Vector3(_hip_curve(t), 0.0, -2.0)
	p["UpperLeg.R"] = Vector3(_hip_curve(t + 0.5), 0.0, 2.0)
	p["LowerLeg.L"] = Vector3(-_knee_curve(t), 0.0, 0.0)
	p["LowerLeg.R"] = Vector3(-_knee_curve(t + 0.5), 0.0, 0.0)
	p["Foot.L"] = Vector3(_ankle_curve(t), 0.0, 0.0)
	p["Foot.R"] = Vector3(_ankle_curve(t + 0.5), 0.0, 0.0)
	# 골반: 중간입각(25%, 75%)에 가장 높고 접지(0, 50%)에 낮음. 지지 다리 쪽으로 좌우 이동(최대 2 cm),
	# 스윙 다리 쪽이 앞으로 회전(±5°), 스윙 다리 쪽 골반이 살짝 내려감(경사 ±3°)
	p["hips_pos"] = Vector3(-0.02 * sin(w), 0.02 * (1.0 - cos(2.0 * w)) * 0.5 - 0.012, 0.0)
	p["Hips"] = Vector3(0.0, -5.0 * cos(w), 3.0 * sin(w))
	# 상체: 앞으로 4° 숙이고 골반 반대로 비틀기(어깨 ±5°), 접지 충격마다 미세 끄덕임
	p["Spine"] = Vector3(-3.0, 3.0 * cos(w), -1.5 * sin(w))
	p["Chest"] = Vector3(-1.5 + 0.8 * cos(2.0 * w), 4.0 * cos(w), -1.0 * sin(w))
	p["Neck"] = Vector3(1.0, -2.0 * cos(w), 0.0)
	p["Head"] = Vector3(2.0 - 0.8 * cos(2.0 * w), -2.5 * cos(w), 0.0)
	# 팔: 다리 반대 위상, 앞 +22 / 뒤 −18, 앞으로 올 때 팔꿈치 더 굽힘, 몸에서 살짝 벌림
	var armL := -(2.0 + 20.0 * cos(w))
	var armR := -(2.0 + 20.0 * cos(w + PI))
	p["Shoulder.L"] = Vector3(0.0, 2.0 * cos(w), 0.0)
	p["Shoulder.R"] = Vector3(0.0, 2.0 * cos(w), 0.0)
	p["UpperArm.L"] = Vector3(armL, 0.0, -6.0)
	p["UpperArm.R"] = Vector3(armR, 0.0, 6.0)
	p["LowerArm.L"] = Vector3(14.0 + 14.0 * maxf(0.0, -cos(w)), 0.0, 0.0)
	p["LowerArm.R"] = Vector3(14.0 + 14.0 * maxf(0.0, cos(w)), 0.0, 0.0)
	p["Hand.L"] = Vector3(0.0, 0.0, 0.0)
	p["Hand.R"] = Vector3(0.0, 0.0, 0.0)
	return p


## 종 모양 범프 (중심 c, 폭 w, 주기 1 래핑)
static func _bump(t: float, c: float, w: float) -> float:
	var d := fmod(t - c + 1.5, 1.0) - 0.5
	return exp(-(d * d) / (w * w * 0.5))


static func _hip_curve(t: float) -> float:
	# +30 접지 → −15 (60%) → +30. 코사인 기반에 비대칭 보정
	var w := TAU * fmod(t, 1.0)
	return 7.5 + 22.5 * cos(w) + 4.0 * _bump(t, 0.1, 0.12)


static func _knee_curve(t: float) -> float:
	var tt := fmod(t, 1.0)
	return 5.0 + 13.0 * _bump(tt, 0.12, 0.08) + 24.0 * _bump(tt, 0.60, 0.07) + 57.0 * _bump(tt, 0.74, 0.10)


static func _ankle_curve(t: float) -> float:
	var tt := fmod(t, 1.0)
	return -18.0 * _bump(tt, 0.58, 0.07) + 6.0 * _bump(tt, 0.98, 0.06) - 4.0 * _bump(tt, 0.80, 0.08)


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


## 키 시간을 비율로 늘이거나 줄인다
func _scaled_keys(keys: Array, k: float) -> Array:
	var out := []
	for e in keys:
		out.append([float(e[0]) * k, e[1]])
	return out


## 상체 비틀기(yaw)를 반대로 — 역베기
func _mirror_yaw(keys: Array) -> Array:
	var out := []
	for e in keys:
		var pose: Dictionary = (e[1] as Dictionary).duplicate()
		for n in ["Spine", "Chest", "Head"]:
			if pose.has(n):
				var v: Vector3 = pose[n]
				pose[n] = Vector3(v.x, -v.y, v.z)
		out.append([e[0], pose])
	return out


## 3타: 크게 들어 올렸다 내려치는 강타 (0.33 s, 유효 0.12~0.21)
func _heavy_keys() -> Array:
	var neutral := {"Spine": Vector3(-2, 0, 0), "Chest": Vector3(-1, 0, 0), "Head": Vector3(1, 0, 0),
		"UpperArm.L": Vector3(2, 0, -4), "UpperArm.R": Vector3(2, 0, 4), "LowerArm.L": Vector3(10, 0, 0), "LowerArm.R": Vector3(10, 0, 0),
		"UpperLeg.L": Vector3(0, 0, -1), "UpperLeg.R": Vector3(0, 0, 1), "LowerLeg.L": Vector3(-3, 0, 0), "LowerLeg.R": Vector3(-3, 0, 0),
		"hips_pos": Vector3.ZERO}
	var raise := {"Spine": Vector3(14, -10, 0), "Chest": Vector3(8, -6, 0), "Head": Vector3(-6, 6, 0),
		"UpperArm.L": Vector3(30, 0, -14), "UpperArm.R": Vector3(-150, 0, 20), "LowerArm.L": Vector3(30, 0, 0), "LowerArm.R": Vector3(40, 0, 0),
		"UpperLeg.L": Vector3(16, 0, -6), "UpperLeg.R": Vector3(-10, 0, 8), "LowerLeg.L": Vector3(-14, 0, 0), "LowerLeg.R": Vector3(-12, 0, 0),
		"hips_pos": Vector3(0, -0.02, 0.03)}
	var slam := {"Spine": Vector3(-26, 14, 0), "Chest": Vector3(-12, 8, 0), "Head": Vector3(-6, -8, 0),
		"UpperArm.L": Vector3(-30, 0, -10), "UpperArm.R": Vector3(60, 0, 6), "LowerArm.L": Vector3(20, 0, 0), "LowerArm.R": Vector3(6, 0, 0),
		"UpperLeg.L": Vector3(32, 0, -6), "UpperLeg.R": Vector3(-30, 0, 8), "LowerLeg.L": Vector3(-30, 0, 0), "LowerLeg.R": Vector3(-28, 0, 0),
		"hips_pos": Vector3(0, -0.10, -0.08)}
	var settle := {"Spine": Vector3(-10, 6, 0), "Chest": Vector3(-4, 2, 0), "Head": Vector3(0, -2, 0),
		"UpperArm.L": Vector3(-8, 0, -6), "UpperArm.R": Vector3(30, 0, 6), "LowerArm.L": Vector3(14, 0, 0), "LowerArm.R": Vector3(16, 0, 0),
		"UpperLeg.L": Vector3(12, 0, -3), "UpperLeg.R": Vector3(-12, 0, 4), "LowerLeg.L": Vector3(-12, 0, 0), "LowerLeg.R": Vector3(-12, 0, 0),
		"hips_pos": Vector3(0, -0.04, -0.03)}
	return [[0.0, neutral], [0.11, raise], [0.20, slam], [0.26, settle], [0.33, neutral]]


## 패링: 두 팔을 앞에서 교차해 막는다 (0.35 s)
func _parry_keys() -> Array:
	var neutral := {"Spine": Vector3(-2, 0, 0), "Chest": Vector3(-1, 0, 0), "Head": Vector3(1, 0, 0),
		"UpperArm.L": Vector3(2, 0, -4), "UpperArm.R": Vector3(2, 0, 4), "LowerArm.L": Vector3(10, 0, 0), "LowerArm.R": Vector3(10, 0, 0),
		"UpperLeg.L": Vector3(0, 0, -1), "UpperLeg.R": Vector3(0, 0, 1), "LowerLeg.L": Vector3(-3, 0, 0), "LowerLeg.R": Vector3(-3, 0, 0),
		"hips_pos": Vector3.ZERO}
	var block := {"Spine": Vector3(4, 0, 0), "Chest": Vector3(2, 0, 0), "Head": Vector3(6, 0, 0),
		"UpperArm.L": Vector3(55, 0, 30), "UpperArm.R": Vector3(75, 0, -24), "LowerArm.L": Vector3(85, 0, 0), "LowerArm.R": Vector3(95, 0, 0),
		"UpperLeg.L": Vector3(22, 0, -6), "UpperLeg.R": Vector3(18, 0, 8), "LowerLeg.L": Vector3(-30, 0, 0), "LowerLeg.R": Vector3(-26, 0, 0),
		"hips_pos": Vector3(0, -0.08, 0)}
	var impact := block.duplicate()
	impact["Spine"] = Vector3(10, 0, 0)
	impact["hips_pos"] = Vector3(0, -0.10, 0.04)
	return [[0.0, neutral], [0.05, block], [0.12, impact], [0.24, block], [0.35, neutral]]


## 치명적 판단 대기: 살짝 웅크린 긴장 자세
func _brace_keys() -> Array:
	var brace := {"Spine": Vector3(-6, 0, 0), "Chest": Vector3(-3, 0, 0), "Head": Vector3(4, 0, 0),
		"UpperArm.L": Vector3(20, 0, -12), "UpperArm.R": Vector3(20, 0, 12), "LowerArm.L": Vector3(40, 0, 0), "LowerArm.R": Vector3(40, 0, 0),
		"UpperLeg.L": Vector3(16, 0, -8), "UpperLeg.R": Vector3(16, 0, 8), "LowerLeg.L": Vector3(-24, 0, 0), "LowerLeg.R": Vector3(-24, 0, 0),
		"hips_pos": Vector3(0, -0.07, 0)}
	return [[0.0, brace], [0.20, brace]]


## 사망: 뒤로 휘청이다 쓰러진다 (마지막 포즈 유지)
func _death_keys() -> Array:
	var neutral := {"Spine": Vector3(-2, 0, 0), "Chest": Vector3(-1, 0, 0), "Head": Vector3(1, 0, 0),
		"UpperArm.L": Vector3(2, 0, -4), "UpperArm.R": Vector3(2, 0, 4), "LowerArm.L": Vector3(10, 0, 0), "LowerArm.R": Vector3(10, 0, 0),
		"UpperLeg.L": Vector3(0, 0, -1), "UpperLeg.R": Vector3(0, 0, 1), "LowerLeg.L": Vector3(-3, 0, 0), "LowerLeg.R": Vector3(-3, 0, 0),
		"hips_pos": Vector3.ZERO}
	var stagger := {"Spine": Vector3(18, 0, 0), "Chest": Vector3(10, 0, 0), "Head": Vector3(14, 0, 0),
		"UpperArm.L": Vector3(-30, 0, -20), "UpperArm.R": Vector3(-30, 0, 20), "LowerArm.L": Vector3(20, 0, 0), "LowerArm.R": Vector3(20, 0, 0),
		"UpperLeg.L": Vector3(-10, 0, -4), "UpperLeg.R": Vector3(14, 0, 4), "LowerLeg.L": Vector3(-10, 0, 0), "LowerLeg.R": Vector3(-20, 0, 0),
		"hips_pos": Vector3(0, -0.04, 0.10)}
	var fallen := {"Hips": Vector3(82, 0, 0), "Spine": Vector3(4, 0, 0), "Chest": Vector3(2, 0, 0), "Head": Vector3(-6, 0, 0),
		"UpperArm.L": Vector3(-20, 0, -40), "UpperArm.R": Vector3(-10, 0, 50), "LowerArm.L": Vector3(10, 0, 0), "LowerArm.R": Vector3(30, 0, 0),
		"UpperLeg.L": Vector3(-6, 0, -6), "UpperLeg.R": Vector3(8, 0, 6), "LowerLeg.L": Vector3(-14, 0, 0), "LowerLeg.R": Vector3(-6, 0, 0),
		"hips_pos": Vector3(0, -0.82, 0.30)}
	return [[0.0, neutral], [0.14, stagger], [0.42, fallen], [0.60, fallen]]


## 사격: 오른팔을 앞으로 뻗어 조준(왼팔은 받침), 반동으로 살짝 뒤로, 복귀
func _shoot_keys() -> Array:
	var aim := {"Spine": Vector3(-4, 12, 0), "Chest": Vector3(-2, 6, 0), "Head": Vector3(0, -8, 0),
		"UpperArm.R": Vector3(88, 0, 4), "LowerArm.R": Vector3(6, 0, 0), "UpperArm.L": Vector3(60, 0, 22), "LowerArm.L": Vector3(45, 0, 0),
		"UpperLeg.L": Vector3(6, 0, -3), "UpperLeg.R": Vector3(-8, 0, 3), "LowerLeg.L": Vector3(-6, 0, 0), "LowerLeg.R": Vector3(-8, 0, 0),
		"hips_pos": Vector3(0, -0.015, 0)}
	var recoil := aim.duplicate()
	recoil["UpperArm.R"] = Vector3(96, 0, 4)
	recoil["LowerArm.R"] = Vector3(18, 0, 0)
	recoil["Spine"] = Vector3(2, 12, 0)
	var settle := aim.duplicate()
	settle["UpperArm.R"] = Vector3(80, 0, 4)
	return [[0.0, aim], [0.03, recoil], [0.10, settle], [SHOOT_LEN, aim]]


## 던지기: 뒤로 당겼다가 오버핸드로 앞으로
func _throw_keys() -> Array:
	var neutral := {"Spine": Vector3(-2, 0, 0), "Chest": Vector3(-1, 0, 0), "Head": Vector3(1, 0, 0),
		"UpperArm.L": Vector3(2, 0, -4), "UpperArm.R": Vector3(2, 0, 4), "LowerArm.L": Vector3(10, 0, 0), "LowerArm.R": Vector3(10, 0, 0),
		"UpperLeg.L": Vector3(0, 0, -1), "UpperLeg.R": Vector3(0, 0, 1), "LowerLeg.L": Vector3(-3, 0, 0), "LowerLeg.R": Vector3(-3, 0, 0),
		"hips_pos": Vector3.ZERO}
	var windup := {"Spine": Vector3(6, -22, 0), "Chest": Vector3(4, -10, 0), "Head": Vector3(0, 10, 0),
		"UpperArm.L": Vector3(30, 0, -12), "UpperArm.R": Vector3(-70, 0, 60), "LowerArm.L": Vector3(20, 0, 0), "LowerArm.R": Vector3(100, 0, 0),
		"UpperLeg.L": Vector3(12, 0, -5), "UpperLeg.R": Vector3(-12, 0, 6), "LowerLeg.L": Vector3(-10, 0, 0), "LowerLeg.R": Vector3(-14, 0, 0),
		"hips_pos": Vector3(0, -0.02, 0.02)}
	var release := {"Spine": Vector3(-16, 26, 0), "Chest": Vector3(-8, 10, 0), "Head": Vector3(-4, -8, 0),
		"UpperArm.L": Vector3(-20, 0, -8), "UpperArm.R": Vector3(120, 0, 10), "LowerArm.L": Vector3(16, 0, 0), "LowerArm.R": Vector3(10, 0, 0),
		"UpperLeg.L": Vector3(22, 0, -5), "UpperLeg.R": Vector3(-20, 0, 6), "LowerLeg.L": Vector3(-16, 0, 0), "LowerLeg.R": Vector3(-24, 0, 0),
		"hips_pos": Vector3(0, -0.04, -0.05)}
	return [[0.0, neutral], [0.08, windup], [0.17, release], [THROW_LEN, neutral]]


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
